require "json"

space_slug = "training"
space_name = "Training Template"
scheme = "https"
domain = "kinops.io"
integration_username = "integration-user"
integration_password = "changeit"

task_signature_secret = "1234asdf5678jkl;"

requesting_user_displayname = "Some User"
requesting_user_username = "some.user@example.com"
requesting_user_email = "some.user@example.com"

smtp_server = ""
smtp_port = "587"
smtp_tls = "true"
smtp_username = "sample-user"
smtp_password = "changeit"
smtp_from_address = "support@example.com"


opts = {
  "core" => {
    "api" => "#{scheme}://#{space_slug}.#{domain}/app/api/v1",
    "agent_api" => "#{scheme}://#{space_slug}.#{domain}/app/components/agents/system/app/api/v1",
    "proxy_url" => "#{scheme}://#{space_slug}.#{domain}/app/components",
    "server" => "#{scheme}://#{space_slug}.#{domain}",
    "space_slug" => "#{space_slug}",
    "space_name" => "#{space_name}",
    "service_user_username" => "#{integration_username}",
    "service_user_password" => "#{integration_password}",
    "task_api_v1" => "#{scheme}://#{space_slug}.#{domain}/app/components/task/app/api/v1",
    "task_api_v2" => "#{scheme}://#{space_slug}.#{domain}/app/components/task/app/api/v2"
  },
  "task" => {
    "api" => "#{scheme}://#{space_slug}.#{domain}/kinetic-task/app/api/v1",
    "api_v2" => "#{scheme}://#{space_slug}.#{domain}/kinetic-task/app/api/v2",
    "component_type" => "task",
    "server" => "#{scheme}://#{space_slug}.#{domain}/kinetic-task",
    "space_slug" => "#{space_slug}",
    "signature_secret" => "#{task_signature_secret}"
  },
  "http_options" => {
    "log_level" => "info",
    "log_output" => "stdout"
  },
  "data" => {
    "requesting_user" => {
      "username" => "#{requesting_user_username}",
      "displayName" => "#{requesting_user_displayname}",
      "email" => "#{requesting_user_email}",
    },
    "users" => [],
    "space" => {
      "attributesMap" => {
        "Platform Host URL" => [ "#{scheme}://#{space_slug}.#{domain}" ]
      }
    },
    "handlers" => {
      "kinetic_core_system_api_v1" => {
        "api_username" => "#{integration_username}",
        "api_password" => "#{integration_password}",
        "api_location" => "#{scheme}://#{space_slug}.#{domain}/app/api/v1"
      }
    },
    "smtp" => {
      "server" => "#{smtp_server}",
      "port" => "#{smtp_port}",
      "tls" => "#{smtp_tls}",
      "username" => "#{smtp_username}",
      "password" => "#{smtp_password}",
      "from_address" => "#{smtp_from_address}"
    }
  }
}

puts opts.to_json.inspect
