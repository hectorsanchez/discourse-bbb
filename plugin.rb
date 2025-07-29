# frozen_string_literal: true

# name: discourse-bbb
# about: Integrate BigBlueButton in Discourse.
# version: 1.0.0
# authors: Penar Musaraj
# url: https://github.com/pmusaraj/discourse-bbb

enabled_site_setting :bbb_enabled

register_asset "stylesheets/common/bbb.scss"
register_svg_icon "video"

# Registrar el BBCode [wrap] 
register_bbcode 'wrap' do |contents, args|
  # Parsear argumentos separados por comas
  # Formato: [wrap=discourse-bbb,meetingName,startDate,startTime,duration]
  data_attrs = ''
  
  if args
    parts = args.split(',')
    if parts.length >= 1 && parts[0] == 'discourse-bbb'
      data_attrs = 'data-wrap="discourse-bbb"'
      
      # Agregar atributos adicionales si existen
      if parts[1] # meetingName
        data_attrs += " data-meetingname=\"#{CGI.escapeHTML(parts[1])}\""
      end
      if parts[2] # startDate
        data_attrs += " data-startdate=\"#{CGI.escapeHTML(parts[2])}\""
      end
      if parts[3] # startTime  
        data_attrs += " data-starttime=\"#{CGI.escapeHTML(parts[3])}\""
      end
      if parts[4] # duration
        data_attrs += " data-duration=\"#{CGI.escapeHTML(parts[4])}\""
      end
    end
  end
  
  # Retornar HTML
  "<div class=\"wrap-container\" #{data_attrs}>#{contents}</div>"
end

after_initialize do
  [
    "../app/controllers/bbb_client_controller",
  ].each { |path| require File.expand_path(path, __FILE__) }

  module ::BigBlue
    PLUGIN_NAME ||= "discourse-bbb".freeze

    class Engine < ::Rails::Engine
      engine_name BigBlue::PLUGIN_NAME
      isolate_namespace BigBlue
    end
  end

  BigBlue::Engine.routes.draw do
    post '/create' => 'bbb_client#create', constraints: { format: :json }
    get '/status/:meeting_id' => 'bbb_client#status', constraints: { format: :json }
  end

  Discourse::Application.routes.append do
    mount ::BigBlue::Engine, at: "/bbb"
  end
end
