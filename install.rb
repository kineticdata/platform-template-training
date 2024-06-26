# Action options must be passed as a JSON string
#
# Format with example values:
#
# {
#   "core" => {
#     "api" => "http://localhost:8080/kinetic/app/api/v1",
#     "agent_api" => "http://localhost:8080/kinetic/foo/app/components/agent/app/api/v1",
#     "proxy_url" => "http://localhost:8080/kinetic/foo/app/components",
#     "server" => "http://localhost:8080/kinetic",
#     "space_slug" => "foo",
#     "space_name" => "Foo",
#     "service_user_username" => "service_user_username",
#     "service_user_password" => "secret",
#     "task_api_v1" => "http://localhost:8080/kinetic/foo/app/components/task/app/api/v1",
#     "task_api_v2" => "http://localhost:8080/kinetic/foo/app/components/task/app/api/v2"
#   },
#   "task" => {
#     "api" => "http://localhost:8080/kinetic-task/app/api/v1",
#     "api_v2" => "http://localhost:8080/kinetic-task/app/api/v2",
#     "component_type" => "task",
#     "server" => "http://localhost:8080/kinetic-task",
#     "space_slug" => "foo",
#     "signature_secret" => "1234asdf5678jkl;"
#   },
#   "http_options" => {
#     "log_level" => "info",
#     "gateway_retry_limit" => 5,
#     "gateway_retry_delay" => 1.0,
#     "ssl_ca_file" => "/app/ssl/tls.crt",
#     "ssl_verify_mode" => "peer"
#   },
#   "data" => {
#     "requesting_user" => {
#       "username" => "joe.user",
#       "displayName" => "Joe User",
#       "email" => "joe.user@google.com",
#     },
#     "users" => [
#       {
#         "username" => "joe.user"
#       }
#     ],
#     "space" => {
#       "attributesMap" => {
#         "Platform Host URL" => [ "http://localhost:8080" ]
#       }
#     },
#     "handlers" => {
#       "kinetic_core_system_api_v1" => {
#         "api_username" => "admin",
#         "api_password" => "password",
#         "api_location" => "http://localhost:8080/app/api/v1"
#       }
#     }
#     "smtp" => {
#       "server" => "smtp.gmail.com",
#       "port" => "587",
#       "tls" => "true",
#       "username" => "joe.blow@gmail.com",
#       "password" => "test",
#       "from_address" => "wally@kinops.io"
#     }
#   }
# }

require "logger"
require "json"

template_name = "platform-template-training"

logger = Logger.new(STDERR)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  "[#{date_format}] #{severity}: #{msg}\n"
end

raise "Missing JSON argument string passed to template install script" if ARGV.empty?
begin
  vars = JSON.parse(ARGV[0])
  # initialize the data property unless it already exists
  vars["data"] = {} unless vars.has_key?("data")
rescue => e
  raise "Template #{template_name} install error: #{e.inspect}"
end

# determine the directory paths
platform_template_path = File.dirname(File.expand_path(__FILE__))
core_path = File.join(platform_template_path, "core")
task_path = File.join(platform_template_path, "task")

# ------------------------------------------------------------------------------
# setup
# ------------------------------------------------------------------------------

logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }

require "kinetic_sdk"
require File.join(File.expand_path(File.dirname(__FILE__)), "workflows.rb")

# ------------------------------------------------------------------------------
# common
# ------------------------------------------------------------------------------

# task source configurations
task_source_properties = {
  "Kinetic Platform" => {
    "Space Slug" => nil,
    "Web Server" => vars["core"]["server"],
    "Proxy Username" => vars["core"]["service_user_username"],
    "Proxy Password" => vars["core"]["service_user_password"],
  },
}

# smtp data
if vars["data"].has_key? "smtp"
  smtp = vars["data"]["smtp"]
  pw = smtp["password"]
  smtp["password"] = "************"
  logger.info "The provided smtp variable data is: #{smtp}"
  smtp["password"] = pw
else
  logger.info "The smtp variable data was not provided to the \"#{template_name}\" template"
  logger.info "Provided data: #{vars["data"]}"
  smtp = {}
end

# task handler info values
task_handler_configurations = {
  "smtp_email_send" => {
    "server" => smtp["server"] || smtp["host"] || "mysmtp.com",
    "port" => (smtp["port"] || "25").to_s,
    "tls" => (smtp["tls"] || smtp["tlsEnabled"] || "true").to_s,
    "username" => smtp["username"] || "joe.blow",
    "password" => smtp["password"] || "password",
  },
}
task_handler_configurations = task_handler_configurations.merge(vars["data"]["handlers"] || {})

http_options = (vars["http_options"] || {}).each_with_object({}) do |(k, v), result|
  result[k.to_sym] = v
end

# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{core_path}" }),
})

# Add Kinetic Platform Bridge Adapter
logger.info "Configuring Kinetic Platform Bridge and removing Kinetic Core Bridge"
platform_bridge_body = { "slug": "kinetic-platform",
                        "adapterClass": "com.kineticdata.bridgehub.adapter.kinetic.platform.KineticCoreAdapter",
                        "properties": { "Username": vars["core"]["service_user_username"],
                                        "Password": vars["core"]["service_user_password"],
                                        "Kinetic Core Space Url": vars["core"]["server"] } }

agent_url = "#{vars["core"]["server"]}/app/components/agents/system/app/api/v1/bridges"
agent_conn = KineticSdk::CustomHttp.new({
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
})
agent_conn.post(agent_url, platform_bridge_body, agent_conn.default_headers)
agent_conn.delete("#{agent_url}/kinetic-core")

# cleanup any kapps that are precreated with the space (catalog)
(space_sdk.find_kapps.content["kapps"] || []).each do |item|
  space_sdk.delete_kapp(item["slug"])
end

# cleanup any existing spds that are precreated with the space (everyone, etc)
space_sdk.delete_space_security_policy_definitions

logger.info "Installing the core components for the \"#{template_name}\" template."
logger.info "  installing with api: #{space_sdk.api_url}"

# import the space for the template
space_sdk.import_space(vars["core"]["space_slug"])

# set space attributes
space_attributes_map = {
  "Web Server Url" => [vars["core"]["server"]],
}

# update the space properties
#   set required space attributes
#   set space name from vars
space_sdk.update_space({
  "attributesMap" => space_attributes_map,
  "name" => vars["core"]["space_name"],
})

# import submissions
Dir["#{core_path}/**/*.ndjson"].sort.each do |filename|
  form_slug = filename.match(/forms\/(.+)\/submissions\.ndjson/)[1]
  kapp_slug = filename.match(/kapps\/(.+)\/forms/)[1]

  File.readlines(filename).each do |line|
    submission = JSON.parse(line)
    body = { "values" => submission["values"] }
    space_sdk.add_submission(kapp_slug, form_slug, body).content
  end
end

# update each bridge model mapping with the corresponding bridge in the agent platform component
space_sdk.find_bridge_models.content["models"].each do |model|
  exported_model = space_sdk.find_bridge_model(model["name"], { "export" => true }).content["model"]
  exported_model["mappings"].each do |mapping|
    mapping.delete("bridgeName")
    mapping["bridgeSlug"] = "kinetic-platform"
    space_sdk.update_bridge_model_mapping(model["name"], mapping["name"], mapping)
  end
end

# create any additional users that were specified
(vars["data"]["users"] || []).each do |user|
  space_sdk.add_user(user)
end

# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------

task_sdk = KineticSdk::Task.new({
  app_server_url: "#{vars["core"]["proxy_url"]}/task",
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{task_path}" }),
})

logger.info "Installing the task components for the \"#{template_name}\" template."
logger.info "  installing with api: #{task_sdk.api_url}"

# cleanup playground data
task_sdk.delete_categories
task_sdk.delete_groups
task_sdk.delete_users
task_sdk.delete_policy_rules

# import access keys
Dir["#{task_path}/access-keys/*.json"].each do |file|
  # parse the access_key file
  required_access_key = JSON.parse(File.read(file))
  # determine if access_key is already installed
  not_installed = task_sdk.find_access_key(required_access_key["identifier"]).status == 404
  # set access key secret
  required_access_key["secret"] = "SETME"
  # add or update the access key
  not_installed ?
    task_sdk.add_access_key(required_access_key) :
    task_sdk.update_access_key(required_access_key["identifier"], required_access_key)
end

# import data from template and force overwrite where necessary
task_sdk.import_groups
task_sdk.import_handlers(true)
task_sdk.import_policy_rules

# import sources
Dir["#{task_path}/sources/*.json"].each do |file|
  # parse the source file
  required_source = JSON.parse(File.read(file))
  # determine if source is already installed
  not_installed = task_sdk.find_source(required_source["name"]).status == 404
  # set source properties
  required_source["properties"] = task_source_properties[required_source["name"]] || {}
  # add or update the source
  not_installed ? task_sdk.add_source(required_source) : task_sdk.update_source(required_source)
end

# configure handler info values
task_sdk.find_handlers.content["handlers"].each do |handler|
  handler_definition_id = handler["definitionId"]

  if task_handler_configurations.has_key?(handler_definition_id)
    logger.info "Updating handler #{handler_definition_id}"
    task_sdk.update_handler(handler_definition_id, {
      "properties" => task_handler_configurations[handler_definition_id],
    })
  else
    if handler_definition_id.start_with?("kinetic_core_api_v1")
      logger.info "Updating handler #{handler_definition_id}"
      task_sdk.update_handler(handler_definition_id, {
        "properties" => {
          "api_location" => vars["core"]["api"],
          "api_username" => vars["core"]["service_user_username"],
          "api_password" => vars["core"]["service_user_password"],
        },
      })
    elsif handler_definition_id.start_with?("kinetic_task_api_v1")
      logger.info "Updating handler #{handler_definition_id}"
      task_sdk.update_handler(handler_definition_id, {
        "properties" => {
          "api_location" => vars["core"]["task_api_v1"],
          "api_username" => vars["core"]["service_user_username"],
          "api_password" => vars["core"]["service_user_password"],
          "api_access_key_identifier" => nil,
          "api_access_key_secret" => nil,
        },
      })
    elsif handler_definition_id.start_with?("kinetic_task_api_v2")
      logger.info "Updating handler #{handler_definition_id}"
      task_sdk.update_handler(handler_definition_id, {
        "properties" => {
          "api_location" => vars["core"]["task_api_v2"],
          "api_username" => vars["core"]["service_user_username"],
          "api_password" => vars["core"]["service_user_password"],
        },
      })
    elsif handler_definition_id.start_with?("kinetic_request_ce_notification_template_send_v")
      task_sdk.update_handler(handler_definition_id, {
        "properties" => task_handler_configurations["kinetic_request_ce_notification_template_send"],
      })
    elsif handler_definition_id.start_with?("smtp_email_send")
      task_sdk.update_handler(handler_definition_id, {
        "properties" => task_handler_configurations["smtp_email_send"],
      })
    elsif handler_definition_id.start_with?("kinetic_request_ce")
      task_sdk.update_handler(handler_definition_id, {
        "properties" => {
          "api_server" => vars["core"]["server"],
          "api_username" => vars["core"]["service_user_username"],
          "api_password" => vars["core"]["service_user_password"],
          "space_slug" => nil,
        },
      })
    elsif handler_definition_id.start_with?("kinetic_agent_handler_execute_v")
      task_sdk.update_handler(handler_definition_id, {
        "properties" => {
          "api_server" => vars["core"]["server"],
          "api_username" => vars["core"]["service_user_username"],
          "api_password" => vars["core"]["service_user_password"],
          "space_slug" => nil,
        },
      })
    end
  end
end

# update the engine properties
task_sdk.update_engine({
  "Max Threads" => "5",
  "Sleep Delay" => "1",
  "Trigger Query" => "'Selection Criterion'=null",
})

# import routines and force overwrite
task_sdk.import_routines(true)

# import categories
task_sdk.import_categories

# import trees and force overwrite
task_sdk.import_trees(true)

# import workflows
import_workflows(core_path, space_sdk)

# ------------------------------------------------------------------------------
# service portal specific
# ------------------------------------------------------------------------------

# create requesting user that was specified
if (vars["data"]["requesting_user"])
  space_sdk.add_user({
    "username" => vars["data"]["requesting_user"]["username"],
    "email" => vars["data"]["requesting_user"]["email"],
    "displayName" => vars["data"]["requesting_user"]["displayName"],
    "password" => "#{vars["data"]["requesting_user"]["email"]}2024",
    "enabled" => true,
    "spaceAdmin" => true,
  })
end

# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished installing the \"#{template_name}\" template."
