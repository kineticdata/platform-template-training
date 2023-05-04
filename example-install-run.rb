require "json"

space_name = "Training Template"
space_slug = "training"
server = "https://#{space_slug}.kinops.io"
username = ""
password = ""

data = {
  "core" => {
    "api" => "#{server}/app/api/v1",
    "agent_api" => "#{server}/app/components/agent/app/api/v1",
    "proxy_url" => "#{server}/app/components",
    "server" => server,
    "space_slug" => space_slug,
    "space_name" => space_name,
    "service_user_username" => username,
    "service_user_password" => password,
    "task_api_v1" => "#{server}/app/components/task/app/api/v1",
    "task_api_v2" => "#{server}/app/components/task/app/api/v2",
  },
  "http_options" => {
    "log_level" => "info",
    "log_output" => "stderr",
  },
  "task" => {
     "api" => "#{server}/app/components/task/app/api/v2",
     "api_v2" => "#{server}/app/components/task/app/api/v2",
     "component_type" => "task",
     "server" => "#{server}/app/components/task",
     "space_slug" => space_slug,
     "signature_secret" => "1234asdf5678jkl;"
   },
   "data" => {
     "requesting_user" => {
       "username" => "joe.user",
       "displayName" => "Joe User",
       "email" => "joe.user@test.com",
     },
     "users" => [
       {
         "username" => "joe.user"
       }
     ],
     "space" => {
       "attributesMap" => {
         "Platform Host URL" => [ "#{server}" ]
       }
     },
     "handlers" => {
       "kinetic_core_system_api_v1" => {
         "api_username" => username,
         "api_password" => password,
         "api_location" => "#{server}/api/v1"
       }
     },
     "smtp" => {
       "server" => "smtp.gmail.com",
       "port" => "587",
       "tls" => "true",
       "username" => "joe.blow@gmail.com",
       "password" => "test",
       "from_address" => "wally@kinops.io"
     }
   }
}

puts "Installing #{space_slug}"
`ruby install.rb #{data.to_json.inspect}`
