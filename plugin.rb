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
  on(:post_process_cooked) do |doc, post|
    doc.css('div[data-wrap="discourse-bbb"]').each do |element|
      # El contenido ya está procesado por el initializer de JavaScript
      # Solo necesitamos asegurar que el elemento tenga la clase correcta
      element.add_class('bbb-meeting-container')
    end
  end
end
