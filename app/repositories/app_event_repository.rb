module VCAP::CloudController
  module Repositories
    class AppEventRepository
      CENSORED_FIELDS   = [:encrypted_environment_json,
                           :command,
                           :environment_json,
                           :environment_variables,
                           :docker_credentials].freeze
      CENSORED_MESSAGE  = 'PRIVATE DATA HIDDEN'.freeze
      SYSTEM_ACTOR_HASH = { guid: 'system', type: 'system', name: 'system', user_name: 'system' }.freeze

      def create_app_exit_event(app, droplet_exited_payload)
        Loggregator.emit(app.guid, "App instance exited with guid #{app.guid} payload: #{droplet_exited_payload}")

        actor    = { name: app.name, guid: app.guid, type: 'app' }
        metadata = droplet_exited_payload.slice('instance', 'index', 'exit_status', 'exit_description', 'reason')
        create_app_audit_event('app.crash', app, app.space, actor, metadata)
      end

      def record_app_update(app, space, user_audit_info, request_attrs)
        audit_hash = app_audit_hash(request_attrs)
        Loggregator.emit(app.guid, "Updated app with guid #{app.guid} (#{audit_hash})")

        actor    = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        metadata = { request: audit_hash }
        create_app_audit_event('audit.app.update', app, space, actor, metadata)
      end

      def record_app_map_droplet(app, space, user_audit_info, request_attrs)
        audit_hash = app_audit_hash(request_attrs)
        Loggregator.emit(app.guid, "Updated app with guid #{app.guid} (#{audit_hash})")

        actor    = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        metadata = { request: audit_hash }
        create_app_audit_event('audit.app.droplet.mapped', app, space, actor, metadata)
      end

      def record_app_create(app, space, user_audit_info, request_attrs)
        Loggregator.emit(app.guid, "Created app with guid #{app.guid}")

        actor    = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        metadata = { request: app_audit_hash(request_attrs) }
        create_app_audit_event('audit.app.create', app, space, actor, metadata)
      end

      def record_app_start(app, user_audit_info)
        Loggregator.emit(app.guid, "Starting app with guid #{app.guid}")

        actor = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        create_app_audit_event('audit.app.start', app, app.space, actor, nil)
      end

      def record_app_restart(app, user_audit_info)
        Loggregator.emit(app.guid, "Restarted app with guid #{app.guid}")

        actor = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, type: 'user', user_name: user_audit_info.user_name }
        create_app_audit_event('audit.app.restart', app, app.space, actor, nil)
      end

      def record_app_stop(app, user_audit_info)
        Loggregator.emit(app.guid, "Stopping app with guid #{app.guid}")

        actor = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        create_app_audit_event('audit.app.stop', app, app.space, actor, nil)
      end

      def record_app_delete_request(app, space, user_audit_info, recursive=nil)
        Loggregator.emit(app.guid, "Deleted app with guid #{app.guid}")

        actor    = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        metadata = nil
        unless recursive.nil?
          metadata = { request: { recursive: recursive } }
        end
        create_app_audit_event('audit.app.delete-request', app, space, actor, metadata)
      end

      def actor_or_system_hash(user_audit_info)
        return SYSTEM_ACTOR_HASH if user_audit_info.user_guid.nil?
        { guid: user_audit_info.user_guid, name: user_audit_info.user_email, user_name: user_audit_info.user_name, type: 'user' }
      end

      def record_map_route(app, route, user_audit_info, route_mapping: nil)
        actor_hash = actor_or_system_hash(user_audit_info)
        metadata   = { route_guid: route.guid }
        if route_mapping
          metadata[:app_port]           = route_mapping.app_port
          metadata[:route_mapping_guid] = route_mapping.guid
          metadata[:process_type]       = route_mapping.process_type
        end
        create_app_audit_event('audit.app.map-route', app, app.space, actor_hash, metadata)
      end

      def record_unmap_route(app, route, user_audit_info, route_mapping_guid, process_type)
        actor_hash = actor_or_system_hash(user_audit_info)
        metadata   = { route_guid: route.guid, route_mapping_guid: route_mapping_guid, process_type: process_type }
        create_app_audit_event('audit.app.unmap-route', app, app.space, actor_hash, metadata)
      end

      def record_app_restage(app, user_audit_info)
        actor_hash = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        create_app_audit_event('audit.app.restage', app, app.space, actor_hash, {})
      end

      def record_src_copy_bits(dest_app, src_app, user_audit_info)
        actor_hash = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        metadata   = { destination_guid: dest_app.guid }
        create_app_audit_event('audit.app.copy-bits', src_app, src_app.space, actor_hash, metadata)
      end

      def record_dest_copy_bits(dest_app, src_app, user_audit_info)
        actor_hash = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        metadata   = { source_guid: src_app.guid }
        create_app_audit_event('audit.app.copy-bits', dest_app, dest_app.space, actor_hash, metadata)
      end

      def record_app_ssh_unauthorized(app, user_audit_info, index)
        actor_hash = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        create_app_audit_event('audit.app.ssh-unauthorized', app, app.space, actor_hash, { index: index })
      end

      def record_app_ssh_authorized(app, user_audit_info, index)
        actor_hash = { name: user_audit_info.user_email, guid: user_audit_info.user_guid, user_name: user_audit_info.user_name, type: 'user' }
        create_app_audit_event('audit.app.ssh-authorized', app, app.space, actor_hash, { index: index })
      end

      private

      def create_app_audit_event(type, app, space, actor, metadata)
        Event.create(
          space:          space,
          type:           type,
          timestamp:      Sequel::CURRENT_TIMESTAMP,
          actee:          app.guid,
          actee_type:     'app',
          actee_name:     app.name,
          actor:          actor[:guid],
          actor_type:     actor[:type],
          actor_name:     actor[:name],
          actor_username: actor[:user_name],
          metadata:       metadata
        )
      end

      def app_audit_hash(request_attrs)
        request_attrs.dup.tap do |changes|
          CENSORED_FIELDS.map(&:to_s).each do |censored|
            changes[censored] = CENSORED_MESSAGE if changes.key?(censored)
          end

          v2_buildpack = changes.key?('buildpack')
          v3_buildpack = changes.key?('lifecycle') && changes['lifecycle'].key?('data') && changes['lifecycle']['data'].key?('buildpack')

          if v2_buildpack
            buildpack_attr = changes['buildpack']
            changes['buildpack'] = CloudController::UrlSecretObfuscator.obfuscate(buildpack_attr) if buildpack_attr
          elsif v3_buildpack
            buildpack_attr = changes['lifecycle']['data']['buildpack']
            changes['lifecycle']['data']['buildpack'] = CloudController::UrlSecretObfuscator.obfuscate(buildpack_attr) if buildpack_attr
          end
        end
      end
    end
  end
end
