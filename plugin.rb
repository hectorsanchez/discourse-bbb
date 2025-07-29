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

  # Registrar el pre-procesador de markdown para [wrap] BBCode
  # Esto debe ejecutarse ANTES de que el markdown parser vea el contenido
  
  reloadable_patch do |plugin|
    PrettyText.singleton_class.prepend(Module.new do
      def cook(text, opts = {})
        # Pre-procesar [wrap] antes del markdown
        if text.include?('[wrap=')
          text = text.gsub(/\[wrap=([^\]]*)\](.*?)\[\/wrap\]/m) do |match|
            args = $1
            content = $2.strip
            
            # Parsear argumentos separados por comas
            data_attrs = ''
            
            if args
              parts = args.split(',')
              if parts.length >= 1 && parts[0] == 'discourse-bbb'
                data_attrs = 'data-wrap="discourse-bbb"'
                
                # Agregar atributos adicionales si existan
                if parts[1] && !parts[1].empty? # meetingName
                  data_attrs += " data-meetingname=\"#{CGI.escapeHTML(parts[1])}\""
                end
                if parts[2] && !parts[2].empty? # startDate
                  data_attrs += " data-startdate=\"#{CGI.escapeHTML(parts[2])}\""
                end
                if parts[3] && !parts[3].empty? # startTime  
                  data_attrs += " data-starttime=\"#{CGI.escapeHTML(parts[3])}\""
                end
                if parts[4] && !parts[4].empty? # duration
                  data_attrs += " data-duration=\"#{CGI.escapeHTML(parts[4])}\""
                end
              end
            end
            
            # Retornar HTML que reemplaza el BBCode
            "<div class=\"wrap-container\" #{data_attrs}>#{content}</div>"
          end
        end
        
        # Llamar al método original con el texto pre-procesado
        super(text, opts)
      end
    end)
  end
end
