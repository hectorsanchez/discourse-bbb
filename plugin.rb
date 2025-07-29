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

  # Registrar el procesador de [wrap] BBCode
  register_custom_html('post') do |doc, post|
    # Buscar elementos que contengan [wrap...] BBCode
    doc.css('p').each do |p|
      next unless p.content =~ /\[wrap.*?\].*?\[\/wrap\]/m
      
      html_content = p.inner_html.gsub(/\[wrap([^\]]*)\](.*?)\[\/wrap\]/m) do |match|
        attrs_string = $1.strip
        content = $2.strip
        
        # Parsear atributos del BBCode
        data_attrs = {}
        attrs_string.scan(/(\w+)="([^"]*)"/).each do |key, value|
          data_attrs["data-#{key}"] = CGI.escapeHTML(value)
        end
        
        # Construir string de data attributes
        data_attr_string = data_attrs.map { |k, v| "#{k}=\"#{v}\"" }.join(' ')
        
        # Retornar HTML convertido
        "<div class=\"wrap-container\" #{data_attr_string}>#{content}</div>"
      end
      
      p.inner_html = html_content
    end
    
    doc
  end
end
