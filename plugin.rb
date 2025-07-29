# frozen_string_literal: true

# name: discourse-bbb
# about: Integrate BigBlueButton in Discourse.
# version: 1.0.0
# authors: Penar Musaraj
# url: https://github.com/pmusaraj/discourse-bbb

enabled_site_setting :bbb_enabled

register_asset "stylesheets/common/bbb.scss"
register_svg_icon "video"

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

  # Registrar el BBCode [wrap] usando la API moderna de Discourse 3.5.0
  # Usamos el mecanismo de markdown allowlist personalizado
  
  # Primero, agregamos el elemento a la allowlist
  allowlist_elements = %w[div]
  allowlist_attributes = {
    "div" => %w[class data-wrap data-meetingname data-startdate data-starttime data-duration data-mode]
  }
  
  # Registrar el procesador de markdown personalizado
  DiscoursePluginRegistry.register_markdown_processor(
    "bbb_wrap",
    priority: 100
  ) do |text|
    text.gsub(/\[wrap=([^\]]*)\](.*?)\[\/wrap\]/m) do |match|
      args = $1
      content = $2.strip
      
      # Parsear argumentos
      data_attrs = ''
      if args
        parts = args.split(',')
        if parts.length >= 1 && parts[0] == 'discourse-bbb'
          data_attrs = 'data-wrap="discourse-bbb"'
          
          if parts[1] && !parts[1].empty?
            data_attrs += " data-meetingname=\"#{CGI.escapeHTML(parts[1])}\""
          end
          if parts[2] && !parts[2].empty?
            data_attrs += " data-startdate=\"#{CGI.escapeHTML(parts[2])}\""
          end
          if parts[3] && !parts[3].empty?
            data_attrs += " data-starttime=\"#{CGI.escapeHTML(parts[3])}\""
          end
          if parts[4] && !parts[4].empty?
            data_attrs += " data-duration=\"#{CGI.escapeHTML(parts[4])}\""
          end
        end
      end
      
      "<div class=\"wrap-container\" #{data_attrs}>#{content}</div>"
    end
  end
end
