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

  # Agregar commit hash para desarrollo (leer desde .discourse-compatibility)
  add_to_serializer(:site, :bbb_plugin_commit_hash) do
    begin
      compatibility_file = File.join(Rails.root, "plugins", "discourse-bbb", ".discourse-compatibility")
      if File.exist?(compatibility_file)
        content = File.read(compatibility_file).strip
        match = content.match(/:\s*([a-f0-9]+)/)
        match ? match[1][0..6] : nil # Primeros 7 caracteres
      end
    rescue
      nil
    end
  end

  # Usar un enfoque más básico que funciona en Discourse 3.5.0.beta8-dev
  # Procesar el BBCode después de que se haya creado el HTML
  
  on(:post_process_cooked) do |doc, post|
    # Buscar elementos que contengan nuestros marcadores shortcode
    doc.css('p').each do |paragraph|
      content = paragraph.inner_html
      
      # Si contiene nuestros marcadores BBB-MEETING, procesarlos
      if content.include?('{{BBB-MEETING:') && content.include?('{{/BBB-MEETING}}')
        new_content = content.gsub(/\{\{BBB-MEETING:([^}]*)\}\}(.*?)\{\{\/BBB-MEETING\}\}/m) do |match|
          meeting_data = $1
          inner_content = $2.strip
          
          # Parsear datos del meeting usando pipe separator
          data_attrs = ''
          if meeting_data
            parts = meeting_data.split('|')
            if parts.length >= 1 && parts[0] == 'discourse-bbb'
              data_attrs = 'data-wrap="discourse-bbb"'
              
              if parts[1] && !parts[1].empty? # meetingName
                data_attrs += " data-meetingname=\"#{CGI.escapeHTML(parts[1])}\""
              end
              if parts[2] && !parts[2].empty? # startDate
                data_attrs += " data-startdate=\"#{CGI.escapeHTML(parts[2])}\""
              end
              if parts[3] && !parts[3].empty? # startTime
                data_attrs += " data-starttime=\"#{CGI.escapeHTML(parts[3])}\""
              end
              if parts[4] && !parts[4].empty? # meeting_id
                data_attrs += " data-meetingid=\"#{CGI.escapeHTML(parts[4])}\""
              end
              if parts[5] && !parts[5].empty? # attendee_pw
                data_attrs += " data-attendeepw=\"#{CGI.escapeHTML(parts[5])}\""
              end
              if parts[6] && !parts[6].empty? # moderator_pw
                data_attrs += " data-moderatorpw=\"#{CGI.escapeHTML(parts[6])}\""
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
