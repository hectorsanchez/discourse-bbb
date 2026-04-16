# frozen_string_literal: true

require 'digest/sha1'
require 'uri'

module BigBlue
  class BbbClientController < ApplicationController
    before_action :ensure_logged_in

    # Reingreso sin fecha en contexto: evita expiración por "nadie se unió" demasiado pronto al recrear sala.
    BBB_DEFAULT_NO_JOIN_EXPIRE_MINUTES = 525_600

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
        
        # Configuración: minutos antes de la hora programada para permitir acceso
        minutes_before = 10

        # Siempre crear el meeting (sin límite de duración)
        meeting_data = create_new_meeting(params)
        return render json: { error: 'Could not create meeting' } unless meeting_data

        # Verificar si está dentro del rango para acceso inmediato (solo inicio, sin fin)
        # Permitir acceso desde X minutos antes de la hora programada
        allowed_time = start_datetime - (minutes_before * 60)
        if now >= allowed_time
          # Si está dentro del rango, crear y unir inmediatamente PERO también devolver datos para el botón
          url = create_and_join(meeting_data)
          unless url
            return render json: { error: 'Could not open meeting' }, status: 502
          end
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
        unless ensure_meeting_before_join(params['meetingID'], params['attendeePW'], params['moderatorPW'])
          return render json: { error: 'Could not open meeting' }, status: 502
        end
        url = join_existing_meeting(params['meetingID'], params['attendeePW'], params['moderatorPW'])
        render json: { url: url }
      else
        # Funcionalidad existente: usar meeting ID proporcionado (modo legacy)
        url = create_and_join(params)
        unless url
          return render json: { error: 'Could not open meeting' }, status: 502
        end
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

    def ensure_meeting_before_join(meeting_id, attendee_pw, moderator_pw)
      Rails.logger.info(
        "[bbb] ensure_meeting_before_join meetingID=#{meeting_id} user=#{current_user.username}"
      )
      create_params = persistent_meeting_create_params(
        meeting_id: meeting_id,
        attendee_pw: attendee_pw,
        moderator_pw: moderator_pw,
        name: "Discourse Meeting",
        no_join_expire_minutes: BBB_DEFAULT_NO_JOIN_EXPIRE_MINUTES,
        record_meeting: false
      )
      ok, = bbb_execute_create(create_params)
      ok
    end

    def create_and_join(args)
      return false unless SiteSetting.bbb_endpoint && SiteSetting.bbb_secret

      args = args.stringify_keys if args.respond_to?(:stringify_keys)

      meeting_id = args['meetingID']
      attendee_pw = args['attendeePW']
      moderator_pw = args['moderatorPW']
      name = args['meetingName'].presence || "Discourse Meeting"
      no_join = args['meetingExpireIfNoUserJoinedInMinutes'] || BBB_DEFAULT_NO_JOIN_EXPIRE_MINUTES
      record = args['recordMeeting'] == 'true' || args['recordMeeting'] == true

      create_params = persistent_meeting_create_params(
        meeting_id: meeting_id,
        attendee_pw: attendee_pw,
        moderator_pw: moderator_pw,
        name: name,
        no_join_expire_minutes: no_join,
        record_meeting: record
      )
      ok, = bbb_execute_create(create_params)
      return false unless ok

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

      # Validar que la fecha no sea mayor a 90 días desde hoy
      if args['startDate'].present?
        begin
          start_date = Date.parse(args['startDate'])
          max_date = Date.today + 90
          if start_date > max_date
            render json: { error: I18n.t("js.bbb.errors.date_too_far") }, status: 422 and return
          end
        rescue ArgumentError
          render json: { error: I18n.t("js.bbb.errors.invalid_date") }, status: 422 and return
        end
      end

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

      name = args['meetingName'] || "Discourse Meeting"
      record = args['recordMeeting'] == 'true' || args['recordMeeting'] == true

      create_params = persistent_meeting_create_params(
        meeting_id: meeting_id,
        attendee_pw: attendee_pw,
        moderator_pw: moderator_pw,
        name: name,
        no_join_expire_minutes: expire_minutes,
        record_meeting: record
      )

      ok, data = bbb_execute_create(create_params)
      if ok
        Rails.logger.info("New BBB meeting created successfully: #{meeting_id} with duration=0 (infinite)")
        {
          'meetingID' => meeting_id,
          'attendeePW' => attendee_pw,
          'moderatorPW' => moderator_pw,
          'meetingName' => name,
          'meetingExpireIfNoUserJoinedInMinutes' => expire_minutes,
          'recordMeeting' => record
        }
      else
        Rails.logger.error("BBB meeting creation failed: #{data.inspect}")
        false
      end
    end

    def persistent_meeting_create_params(meeting_id:, attendee_pw:, moderator_pw:, name:, no_join_expire_minutes:, record_meeting:)
      params_hash = {
        name: name,
        meetingID: meeting_id,
        attendeePW: attendee_pw,
        moderatorPW: moderator_pw,
        logoutURL: Discourse.base_url,
        welcome: "Welcome to the Discourse meeting!",
        duration: 0,
        endWhenNoModerator: false,
        noAnswerTimeout: 0,
        meetingExpireWhenLastUserLeftInMinutes: 0,
        meetingExpireIfNoUserJoinedInMinutes: no_join_expire_minutes
      }
      if record_meeting
        params_hash[:record] = 'true'
        params_hash[:autoStartRecording] = 'true'
        params_hash[:allowStartStopRecording] = 'true'
      else
        params_hash[:record] = 'false'
      end
      params_hash
    end

    def bbb_execute_create(create_params)
      query = create_params.map do |k, v|
        encoded =
          if v == true || v == false
            v.to_s
          else
            URI.encode_www_form_component(v.to_s)
          end
        "#{k}=#{encoded}"
      end.join('&')
      secret = SiteSetting.bbb_secret
      checksum = Digest::SHA1.hexdigest("create" + query + secret)
      create_url = "#{SiteSetting.bbb_endpoint}create?#{query}&checksum=#{checksum}"

      Rails.logger.info("Creating BBB meeting with params: #{create_params.inspect}")
      Rails.logger.info("BBB create URL (without secret): #{SiteSetting.bbb_endpoint}create?#{query}")

      response = Excon.get(create_url)
      if response.status != 200
        Rails.logger.error("Could not create BBB meeting: HTTP #{response.status}, Body: #{response.body}")
        return [false, response.body]
      end

      data = Hash.from_xml(response.body)
      Rails.logger.info("BBB create response: #{data.inspect}")

      if data['response']['returncode'] == "SUCCESS"
        [true, data]
      else
        Rails.logger.error("BBB meeting creation failed: #{data['response']['message']}")
        Rails.logger.error("Full BBB error response: #{data.inspect}")
        [false, data]
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
