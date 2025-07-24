# Discourse BBB Plugin Development Guide

## Architecture
- **Type**: Discourse plugin for BigBlueButton integration  
- **Language**: Ruby backend (Rails), JavaScript frontend (Ember.js/Glimmer)
- **Structure**: Standard Discourse plugin with `plugin.rb`, `/app`, `/assets`, `/config`
- **API**: RESTful endpoints under `/bbb` namespace with checksum-based authentication

## Commands
- **Test**: No automated tests found - plugin tested manually in Discourse dev environment
- **Lint**: Follow Discourse development guidelines (discourse/discourse repo)
- **Build**: Plugin auto-loaded by Discourse, no separate build step required

## Code Style
- **Ruby**: `frozen_string_literal: true`, 2-space indentation, follow Rails conventions
- **JavaScript**: Modern ES6+ with Ember/Glimmer, use `import` statements, `@tracked`/`@action` decorators
- **Imports**: Use Discourse API imports (`discourse/lib/*`, `discourse-common/lib/*`) 
- **Components**: Glimmer components with class syntax, use `@glimmer/component` base class
- **Modal API**: Use component-based modals (`service:modal.show(Component, {model})`)

## Key Files
- **plugin.rb**: Plugin definition, routes, engine setup
- **app/controllers/bbb_client_controller.rb**: BBB API integration, meeting management
- **assets/javascripts/discourse/initializers/bbb.js.es6**: Plugin initialization, toolbar integration
- **assets/javascripts/discourse/components/modal/insert-bbb.js**: Meeting creation modal
- **config/settings.yml**: Plugin settings (endpoint, secret, permissions)

## Notes
- Compatible with Discourse 3.5.0.beta8-dev
- Uses BBB API with SHA1 checksum authentication
- Always opens meetings in new window due to X-Frame-Options
- Supports both new meeting creation and existing meeting joining
