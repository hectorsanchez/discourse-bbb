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

  # Registrar el token 'wrap' para el parser de Markdown
  register_html_builder('post') do |context|
    if context.post.raw.include?('[wrap')
      context.raw.gsub!(/\[wrap([^\]]*)\](.*?)\[\/wrap\]/m) do |match|
        attrs = $1.strip
        content = $2.strip
        
        # Parsear atributos
        data_attrs = {}
        attrs.scan(/(\w+)="([^"]*)"/).each do |key, value|
          data_attrs["data-#{key}"] = value
        end
        
        # Construir el HTML
        data_attr_string = data_attrs.map { |k, v| "#{k}=\"#{v}\"" }.join(' ')
        "<div class=\"wrap-container\" #{data_attr_string}>#{content}</div>"
      end
    end
    context.raw
  end
end
