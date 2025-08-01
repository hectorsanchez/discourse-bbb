# frozen_string_literal: true

require 'digest/sha1'
require 'uri'

module BigBlue
  class BbbClientController < ApplicationController
    before_action :ensure_logged_in

    def create
      if params['mode'] == 'new'
        # Validar y procesar los nuevos parámetros de fecha
        start_date = params['startDate']
        start_time = params['startTime']

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

        now = Time.now.utc

        # Siempre crear el meeting (sin límite de duración)
        meeting_data = create_new_meeting(params)
        return render json: { error: 'Could not create meeting' } unless meeting_data

        # Verificar si está dentro del rango para acceso inmediato (solo inicio, sin fin)
        if now >= start_datetime
          # Si está dentro del rango, crear y unir inmediatamente PERO también devolver datos para el botón
          url = create_and_join(meeting_data)
          render json: { 
            url: url,  # Abrir inmediatamente
            success: true,  # Y también crear botón
            meeting_id: meeting_data['meetingID'],
            attendee_pw: meeting_data['attendeePW'],
            moderator_pw: meeting_data['moderatorPW'],
            start_time: start_datetime.iso8601,
            message: 'Meeting is now active. Opening immediately and creating button for future access.'
          }
        else
          # Si está fuera del rango, solo retornar éxito (el botón se creará)
          # IMPORTANTE: Incluir passwords para poder unirse después
          render json: { 
            success: true,
            meeting_id: meeting_data['meetingID'],
            attendee_pw: meeting_data['attendeePW'],
            moderator_pw: meeting_data['moderatorPW'],
            start_time: start_datetime.iso8601,
            message: 'Meeting created successfully. Access will be available at the scheduled time.'
          }
        end
      elsif params['mode'] == 'existing' && params['meetingID']
        # Unirse a meeting existente usando meeting ID y passwords guardados
        url = join_existing_meeting(params['meetingID'], params['attendeePW'], params['moderatorPW'])
        render json: { url: url }
      else
        # Funcionalidad existente: usar meeting ID proporcionado (modo legacy)
        url = create_and_join(params)
        render json: { url: url }
      end
    end

    def status
      render json: get_status(params)
    end

    private

    def join_existing_meeting(meeting_id, attendee_pw, moderator_pw)
      return false unless SiteSetting.bbb_endpoint && SiteSetting.bbb_secret
      
      # Construir URL de join usando los passwords correctos guardados
      join_params = {
        fullName: current_user.name || current_user.username,
        meetingID: meeting_id,
        userID: current_user.username,
        # Usar el password correcto según el rol del usuario
        password: is_moderator ? moderator_pw : attendee_pw
      }.to_query

      build_url("join", join_params)
    end

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
      meeting_id = "discourse-#{SecureRandom.hex(8)}-#{Time.now.to_i}"
      attendee_pw = SecureRandom.hex(8)
      moderator_pw = SecureRandom.hex(8)

      # Calcular minutos hasta la fecha/hora seleccionada y sumar 5 minutos extra
      expire_minutes = 5
      if args['startDate'].present? && args['startTime'].present?
        begin
          start_datetime = Time.strptime("#{args['startDate']} #{args['startTime']}", "%Y-%m-%d %H:%M").utc
          now = Time.now.utc
          expire_minutes = ((start_datetime - now) / 60).ceil + 5
          expire_minutes = expire_minutes > 0 ? expire_minutes : 5 # mínimo 5 minutos
        rescue ArgumentError
          expire_minutes = 5
        end
      end

      create_params = {
        name: args['meetingName'] || "Discourse Meeting",
        meetingID: meeting_id,
        attendeePW: attendee_pw,
        moderatorPW: moderator_pw,
        logoutURL: Discourse.base_url,
        welcome: "Welcome to the Discourse meeting!",
        duration: 0,  # 0 = duración indefinida (sin límite de tiempo)
        endWhenNoModerator: false,  # Meeting NO se cierra si no hay moderador
        noAnswerTimeout: 0,  # No eliminar la reunión si nadie entra
        meetingExpireWhenLastUserLeftInMinutes: 0,  # No eliminar la reunión si el último usuario se va
        meetingExpireIfNoUserJoinedInMinutes: expire_minutes # valor calculado + 5 minutos
      }
      
      query = create_params.map { |k, v| "#{k}=#{URI.encode_www_form_component(v)}" }.join('&')
      secret = SiteSetting.bbb_secret
      checksum = Digest::SHA1.hexdigest("create" + query + secret)
      create_url = "#{SiteSetting.bbb_endpoint}create?#{query}&checksum=#{checksum}"
      
      # Log para debug - verificar parámetros enviados
      Rails.logger.info("Creating BBB meeting with params: #{create_params.inspect}")
      Rails.logger.info("BBB create URL (without secret): #{SiteSetting.bbb_endpoint}create?#{query}")
      
      response = Excon.get(create_url)
      if response.status == 200
        data = Hash.from_xml(response.body)
        Rails.logger.info("BBB create response: #{data.inspect}")
        
        if data['response']['returncode'] == "SUCCESS"
          Rails.logger.info("New BBB meeting created successfully: #{meeting_id} with duration=0 (infinite)")
          {
            'meetingID' => meeting_id,
            'attendeePW' => attendee_pw,
            'moderatorPW' => moderator_pw
          }
        else
          Rails.logger.error("BBB meeting creation failed: #{data['response']['message']}")
          Rails.logger.error("Full BBB error response: #{data.inspect}")
          false
        end
      else
        Rails.logger.error("Could not create BBB meeting: HTTP #{response.status}, Body: #{response.body}")
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
