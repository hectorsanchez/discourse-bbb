# frozen_string_literal: true

require 'digest/sha1'
require 'uri'

module BigBlue
  class BbbClientController < ApplicationController
    before_action :ensure_logged_in

    def create
      if params['mode'] == 'new'
        # Validar y procesar los nuevos parámetros de fecha y duración
        start_date = params['startDate']
        start_time = params['startTime']
        duration = params['duration'] || '60' # Default 60 minutos

        if start_date.blank? || start_time.blank?
          return render json: { error: 'Start date and time are required' }, status: 422
        end

        # Parsear fecha y hora en GMT
        begin
          start_datetime = Time.strptime("#{start_date} #{start_time}", "%Y-%m-%d %H:%M").utc
        rescue ArgumentError
          return render json: { error: 'Invalid date or time format' }, status: 422
        end

        # Validar que la fecha no sea anterior a hoy
        today = Time.now.utc.to_date
        if start_datetime.to_date < today
          return render json: { error: 'Start date cannot be in the past' }, status: 422
        end

        duration_minutes = duration.to_i
        if duration_minutes <= 0
          duration_minutes = 60 # Default a 60 minutos si es inválido
        end

        end_datetime = start_datetime + duration_minutes.minutes
        now = Time.now.utc

        # Siempre crear el meeting
        meeting_data = create_new_meeting(params, duration_minutes)
        return render json: { error: 'Could not create meeting' } unless meeting_data

        # Verificar si está dentro del rango para acceso inmediato
        if now >= start_datetime && now <= end_datetime
          # Si está dentro del rango, crear y unir inmediatamente
          url = create_and_join(meeting_data)
          render json: { url: url }
        else
          # Si está fuera del rango, solo retornar éxito (el botón se creará)
          # El acceso se validará cuando se haga clic en el botón
          render json: { 
            success: true,
            meeting_id: meeting_data['meetingID'],
            start_time: start_datetime.iso8601,
            end_time: end_datetime.iso8601,
            message: now < start_datetime ? 'Meeting created successfully. Access will be available at the scheduled time.' : 'Meeting has already ended.'
          }
        end
      else
        # Funcionalidad existente: usar meeting ID proporcionado
        url = create_and_join(params)
        render json: { url: url }
      end
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

    def create_new_meeting(args, duration_minutes = nil)
      return false unless SiteSetting.bbb_endpoint && SiteSetting.bbb_secret
      meeting_id = "discourse-#{SecureRandom.hex(8)}-#{Time.now.to_i}"
      attendee_pw = SecureRandom.hex(8)
      moderator_pw = SecureRandom.hex(8)
      create_params = {
        name: args['meetingName'] || "Discourse Meeting",
        meetingID: meeting_id,
        attendeePW: attendee_pw,
        moderatorPW: moderator_pw,
        logoutURL: Discourse.base_url,
        welcome: "Welcome to the Discourse meeting!"
      }
      # Agregar duración si está presente
      create_params[:duration] = duration_minutes if duration_minutes
      query = create_params.map { |k, v| "#{k}=#{URI.encode_www_form_component(v)}" }.join('&')
      secret = SiteSetting.bbb_secret
      checksum = Digest::SHA1.hexdigest("create" + query + secret)
      create_url = "#{SiteSetting.bbb_endpoint}create?#{query}&checksum=#{checksum}"
      response = Excon.get(create_url)
      if response.status == 200
        data = Hash.from_xml(response.body)
        if data['response']['returncode'] == "SUCCESS"
          Rails.logger.info("New BBB meeting created: #{meeting_id}")
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
