# frozen_string_literal: true

require 'digest/sha1'
require 'uri'

module BigBlue
  class BbbClientController < ApplicationController
    before_action :ensure_logged_in

    def create
      if params['mode'] == 'new'
        # Nueva funcionalidad: crear meeting automáticamente
        meeting_data = create_new_meeting(params)
        return render json: { error: 'Could not create meeting' } unless meeting_data
        
        url = create_and_join(meeting_data)
      else
        # Funcionalidad existente: usar meeting ID proporcionado
        url = create_and_join(params)
      end
      
      render json: { url: url }
    end

    def status
      render json: get_status(params)
    end

    private

    def create_and_join(args)
      return false unless SiteSetting.bbb_endpoint && SiteSetting.bbb_secret

      meeting_id = args['meetingID']
      attendee_pw = args['attendeePW']
      moderator_pw = args['moderatorPW']

      query = {
        meetingID: meeting_id,
        attendeePW: attendee_pw,
        moderatorPW: moderator_pw,
        logoutURL: Discourse.base_url
      }.to_query

      create_url = build_url("create", query)
      response = Excon.get(create_url)

      if response.status != 200
        Rails.logger.warn("Could not create meeting: #{response.inspect}")
        return false
      end

      join_params = {
        fullName: current_user.name || current_user.username,
        meetingID: meeting_id,
        userID: current_user.username,
        password: is_moderator ? moderator_pw : attendee_pw
      }.to_query

      build_url("join", join_params)
    end

    def create_new_meeting(args)
      return false unless SiteSetting.bbb_endpoint && SiteSetting.bbb_secret

      # Generar IDs y passwords únicos y seguros
      meeting_id = "discourse-#{SecureRandom.hex(8)}-#{Time.now.to_i}"
      attendee_pw = SecureRandom.hex(8)
      moderator_pw = SecureRandom.hex(8)

      # Parámetros para crear el meeting
      create_params = {
        name: args['meetingName'] || "Discourse Meeting",
        meetingID: meeting_id,
        attendeePW: attendee_pw,
        moderatorPW: moderator_pw,
        logoutURL: Discourse.base_url,
        welcome: "Welcome to the Discourse meeting!"
      }

      # Construir query con encoding correcto
      query = create_params.map { |k, v| "#{k}=#{URI.encode_www_form_component(v)}" }.join('&')
      
      # Generar checksum
      secret = SiteSetting.bbb_secret
      checksum = Digest::SHA1.hexdigest("create" + query + secret)
      
      # URL completa para crear meeting
      create_url = "#{SiteSetting.bbb_endpoint}create?#{query}&checksum=#{checksum}"
      
      # Hacer la llamada para crear el meeting
      response = Excon.get(create_url)
      
      if response.status == 200
        # Parsear respuesta XML
        data = Hash.from_xml(response.body)
        
        if data['response']['returncode'] == "SUCCESS"
          Rails.logger.info("New BBB meeting created: #{meeting_id}")
          
          # Retornar datos del meeting creado para usar en create_and_join
          {
            'meetingID' => meeting_id,
            'attendeePW' => attendee_pw,
            'moderatorPW' => moderator_pw
          }
        else
          Rails.logger.warn("BBB meeting creation failed: #{data['response']['message']}")
          false
        end
      else
        Rails.logger.warn("Could not create BBB meeting: HTTP #{response.status}")
        false
      end
    end

    def get_status(args)
      return {} unless SiteSetting.bbb_endpoint && SiteSetting.bbb_secret

      url = build_url("getMeetingInfo", "meetingID=#{args['meeting_id']}")
      response = Excon.get(url)
      data = Hash.from_xml(response.body)

      if data['response']['returncode'] == "SUCCESS"
        att = data['response']['attendees']['attendee']
        usernames = att.is_a?(Array) ? att.pluck("userID") : [att["userID"]]
        users = User.where("username IN (?)", usernames)

        avatars = users.map do |s|
          {
            name: s.name || s.username,
            avatar_url: s.avatar_template_url.gsub('{size}', '25')
          }
        end

        {
          count: data['response']['participantCount'],
          avatars: avatars
        }
      else
        {}
      end
    end

    def build_url(type, query)
      secret = SiteSetting.bbb_secret
      checksum = Digest::SHA1.hexdigest(type + query + secret)
      "#{SiteSetting.bbb_endpoint}#{type}?#{query}&checksum=#{checksum}"
    end

    def is_moderator
      return true if current_user.staff?

      group = SiteSetting.bbb_moderator_group_name
      return true if group.present? && current_user.groups.pluck(:name).include?(group)
    end
  end
end
