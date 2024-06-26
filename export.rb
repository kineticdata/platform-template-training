# Action options must be passed as a JSON string
#
# Format with example values:
#
# {
#   "core" => {
#     "api" => "https://foo.web-server/app/api/v1",
#     "agent_api" => "https://foo.web-server/app/components/agent/app/api/v1",
#     "proxy_url" => "https://foo.web-server/app/components",
#     "server" => "https://foo.web-server",
#     "space_slug" => "foo",
#     "space_name" => "Foo",
#     "service_user_username" => "service_user_username",
#     "service_user_password" => "secret",
#     "task_api_v1" => "https://foo.web-server/app/components/task/app/api/v1",
#     "task_api_v2" => "https://foo.web-server/app/components/task/app/api/v2"
#   },
#   "http_options" => {
#     "log_level" => "info",
#     "log_output" => "stderr"
#   }
# }

require 'logger'
require 'json'

template_name = "platform-template-service-portal"

logger = Logger.new(STDERR)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  "[#{date_format}] #{severity}: #{msg}\n"
end

raise "Missing JSON argument string passed to template export script" if ARGV.empty?
begin
  vars = JSON.parse(ARGV[0])
rescue => e
  raise "Template #{template_name} export error: #{e.inspect}"
end


# determine the directory paths
platform_template_path = File.dirname(File.expand_path(__FILE__))
core_path = File.join(platform_template_path, "core")
task_path = File.join(platform_template_path, "task")

# ------------------------------------------------------------------------------
# constants
# ------------------------------------------------------------------------------

# Configuration of which submissions should be exported
SUBMISSIONS_TO_EXPORT = [
  # {"kappSlug" => "datastore", "formSlug" => "notification-data"},
  # {"kappSlug" => "datastore", "formSlug" => "notification-template-dates"}
]

REMOVE_DATA_PROPERTIES = [
  "createdAt",
  "createdBy",
  "updatedAt",
  "updatedBy",
  "closedAt",
  "closedBy",
  "submittedAt",
  "submittedBy",
  "id",
  "authStrategy",
  "key",
  "handle"
]

# ------------------------------------------------------------------------------
# setup
# ------------------------------------------------------------------------------

logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }

require 'kinetic_sdk'
require File.join(File.expand_path(File.dirname(__FILE__)), "workflows.rb")

http_options = (vars["http_options"] || {}).each_with_object({}) do |(k,v),result|
  result[k.to_sym] = v
end

# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

logger.info "Removing files and folders from the existing \"#{template_name}\" template."
FileUtils.rm_rf Dir.glob("#{core_path}/*")

logger.info "Setting up the Core SDK"
space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{core_path}" })
})
task_sdk = KineticSdk::Task.new({
  app_server_url: "#{vars["core"]["proxy_url"]}/task",
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{task_path}" })
})

# fetch export from core service and write to export directory
logger.info "Exporting the core components for the \"#{template_name}\" template."
logger.info "  exporting with api: #{space_sdk.api_url}"
logger.info "   - exporting configuration data (Kapps,forms, etc)"
space_sdk.export_space

# export workflows as these are not included in the export_space method
export_workflows(core_path, space_sdk, task_sdk)

# cleanup properties that should not be committed with export
# bridge keys
Dir["#{core_path}/space/bridges/*.json"].each do |filename|
  bridge = JSON.parse(File.read(filename))
  if bridge.has_key?("key")
    bridge.delete("key")
    File.open(filename, 'w') { |file| file.write(JSON.pretty_generate(bridge)) }
  end
end

# cleanup space
filename = "#{core_path}/space.json"
space = JSON.parse(File.read(filename))
# filestore key
if space.has_key?("filestore") && space["filestore"].has_key?("key")
  space["filestore"].delete("key")
end
# platform components
if space.has_key?("platformComponents")
  if space["platformComponents"].has_key?("task")
    space["platformComponents"].delete("task")
  end
  (space["platformComponents"]["agents"] || []).each_with_index do |agent,idx|
    space["platformComponents"]["agents"][idx]["url"] = ""
  end
end
# rewrite the space file
File.open(filename, 'w') { |file| file.write(JSON.pretty_generate(space)) }

# export submissions
logger.info "  - exporting and writing submission data"
SUBMISSIONS_TO_EXPORT.each do |item|
  logger.info "    - kapp [#{item["kappSlug"]}] form [#{item['formSlug']}]"
  # build directory to write files to
  submission_path = "#{core_path}/space/kapps/#{item['kappSlug']}/forms/#{item['formSlug']}"

  # create folder to write submission data to
  FileUtils.mkdir_p(submission_path, :mode => 0700)

  # build params to pass to the retrieve_form_submissions method
  params = {"include" => "values", "limit" => 1000, "direction" => "ASC"}

  # open the submissions file in write mode
  file = File.open("#{submission_path}/submissions.ndjson", 'w');

  # ensure the file is empty
  file.truncate(0)
  response = nil
  begin
    # get submissions
    response = space_sdk.find_form_submissions(item['kappSlug'], item['formSlug'], params).content
    if response.has_key?("submissions")
      # write each submission on its own line
      (response["submissions"] || []).each do |submission|
        # append each submission (removing the submission unwanted attributes)
        file.puts(JSON.generate(submission.delete_if { |key, value| REMOVE_DATA_PROPERTIES.member?(key)}))
      end
    end
    params['pageToken'] = response['nextPageToken']
    # get next page of submissions if there are more
  end while !response.nil? && !response['nextPageToken'].nil?
  # close the submissions file
  file.close()
end
logger.info "  - submission data export complete"

# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------
logger.info "Removing files and folders from the existing \"#{template_name}\" template."
FileUtils.rm_rf Dir.glob("#{task_path}/*")

logger.info "Exporting the task components for the \"#{template_name}\" template."
logger.info "  exporting with api: #{task_sdk.api_url}"

# export all sources, handlers, groups, policy rules, categories, and access keys
task_sdk.export_all_except_trees

# export trees for all sources except the "Kinetic Request CE" source
(task_sdk.find_sources.content['sourceRoots'] || []).delete_if{ |source| source["name"] == "Kinetic Request CE" }.each do |source|
  task_sdk.export_trees(source['name'])
end

# export routines
task_sdk.export_trees("-")


# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished exporting the \"#{template_name}\" template."
