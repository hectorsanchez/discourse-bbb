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

  # Usar un enfoque más básico que funciona en Discourse 3.5.0.beta8-dev
  # Procesar el BBCode después de que se haya creado el HTML
  
  on(:post_process_cooked) do |doc, post|
    # Buscar elementos <p> que contengan nuestro BBCode
    doc.css('p').each do |paragraph|
      content = paragraph.inner_html
      
      # Si contiene nuestro BBCode, procesarlo
      if content.include?('[wrap=') && content.include?('[/wrap]')
        new_content = content.gsub(/\[wrap=([^\]]*)\](.*?)\[\/wrap\]/m) do |match|
          args = $1
          inner_content = $2.strip
          
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
          
          "<div class=\"wrap-container\" #{data_attrs}>#{inner_content}</div>"
        end
        
        # Reemplazar el contenido del párrafo si cambió
        if new_content != content
          paragraph.inner_html = new_content
        end
      end
    end
  end
end
