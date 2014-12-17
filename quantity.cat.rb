name "quantity"
rs_ca_ver 20131202
short_description "Launch a specified number of servers from Base ST"

parameter "qty_param" do
  type "number"
  label "Quantity"
  default 1
end

parameter "method_param" do
  type "string"
  label "Method"
  allowed_values "array","clone","multiprovision","rawdefinition","realraw"
end

resource "base_server_res", type: "server" do
  name "Base Linux"
  cloud_href "/api/clouds/1"
  ssh_key find(resource_uid: "default")
  security_groups find(name: "default")
  server_template find("Base ServerTemplate for Linux (RSB) (v13.5.5-LTS)", revision: 17)
end

resource "base_array_res", type: "server_array" do
  name "Base Linux"
  cloud_href "/api/clouds/1"
  ssh_key find(resource_uid: "default")
  security_groups find(name: "default")
  server_template find("Base ServerTemplate for Linux (RSB) (v13.5.5-LTS)", revision: 17)
  state "disabled"
  array_type "alert"
  elasticity_params do {
    "bounds" => {
      "min_count" => $qty_param,
      "max_count" => $qty_param
    },
    "pacing" => {
      "resize_calm_time" => 10,
      "resize_down_by" => 1,
      "resize_up_by" => 1
    },
    "alert_specific_params" => {
      "decision_threshold" => 51,
      "voters_tag_predicate" => "notdefined"
    }
  } end
end

operation "launch" do
  description "launch"
  definition "launch"
end

###############################################################################
# BEGIN Include from ../definitions/sys.cat.rb
###############################################################################
# Creates a simple array of the specified size.  The array contains integers
# indexed from 1 up to the specified size
#
# @param $size [int] the desired number of elements in the returned array
#
# @return [Array] a 1 indexed array of the specified size
define sys_get_array_of_size($size) return $array do
  $qty = 1
  $qty_ary = []
  while $qty <= to_n($size) do
    $qty_ary << $qty
    $qty = $qty + 1
  end

  $array = $qty_ary
end

# Creates a "log" entry in the form of an audit entry.  The target of the audit
# entry defaults to the deployment created by the CloudApp, but can be specified
# with the "auditee_href" option.
#
# @param $summary [String] the value to write in the "summary" field of an audit entry
# @param $options [Hash] a hash of options where the possible keys are;
#   * detail [String] the message to write to the "detail" field of the audit entry. Default: ""
#   * notify [String] the event notification catgory, one of (None|Notification|Security|Error).  Default: None
#   * auditee_href [String] the auditee_href (target) for the audit entry. Default: @@deployment.href
#
# @see http://reference.rightscale.com/api1.5/resources/ResourceAuditEntries.html#create
define sys_log($summary,$options) do
  $log_default_options = {
    detail: "",
    notify: "None",
    auditee_href: @@deployment.href
  }

  $log_merged_options = $options + $log_default_options
  rs.audit_entries.create(
    notify: $log_merged_options["notify"],
    audit_entry: {
      auditee_href: $log_merged_options["auditee_href"],
      summary: $summary,
      detail: $log_merged_options["detail"]
    }
  )
end

# Returns a resource collection containing clouds which have the specified relationship.
#
# @param $rel [String] the name of the relationship to filter on.  See cloud
#   media type for a full list
#
# @return [CloudResourceCollection] The clouds which have the specified relationship
#
# @see http://reference.rightscale.com/api1.5/media_types/MediaTypeCloud.html
define sys_get_clouds_by_rel($rel) return @clouds do
  @clouds = concurrent map @cloud in rs.clouds.get() return @cloud_with_rel do
    $rels = select(@cloud.links, {"rel": $rel})
    if size($rels) > 0
      @cloud_with_rel = @cloud
    else
      @cloud_with_rel = rs.clouds.empty()
    end
  end
end

# Fetches the execution id of "this" cloud app using the default tags set on a
# deployment created by SS.
# selfservice:href=/api/manager/projects/12345/executions/54354bd284adb8871600200e
#
# @return [String] The execution ID of the current cloud app
define sys_get_execution_id() return $execution_id do
  call get_tags_for_resource(@@deployment) retrieve $tags_on_deployment
  $href_tag = map $current_tag in $tags_on_deployment return $tag do
    if $current_tag =~ "(selfservice:href)"
      $tag = $current_tag
    end
  end

  if type($href_tag) == "array" && size($href_tag) > 0
    $tag_split_by_value_delimiter = split(first($href_tag), "=")
    $tag_value = last($tag_split_by_value_delimiter)
    $value_split_by_slashes = split($tag_value, "/")
    $execution_id = last($value_split_by_slashes)
  else
    $execution_id = "N/A"
  end

end
###############################################################################
# END Include from ../definitions/sys.cat.rb
###############################################################################


define launch(@base_server_res,@base_array_res,$qty_param,$method_param) return @base_server_res,@base_array_res do
  call sys_get_array_of_size($qty_param) retrieve $qty_ary
  if $method_param == "array"
    provision(@base_array_res)
  end

  if $method_param == "multiprovision"
    @@base_server_res = rs.servers.empty()
    $$definition_hash = to_object(@base_server_res)
    concurrent foreach $qty in $qty_ary do
      $definition_hash = $$definition_hash
      $definition_hash["fields"]["name"] = "foo-"+to_s($qty)
      # Change other things like inputs here
      @new_def = $definition_hash
      provision(@new_def)
    end
    @base_server_res = @@base_server_res
  end

  if $method_param == "clone"
    provision(@base_server_res)
    concurrent foreach $qty in $qty_ary do
      @new_res = @base_server_res.clone()
      @new_res.update(server: {name: "Cloned #"+$qty})
      # Change other things like inputs here
      @new_res.launch()
      sleep_while(@new_res.state != "operational")
    end
  end

  if $method_param == "rawdefinition"
    $$params = {
      "instance" => {
        "cloud_href" => "/api/clouds/1",
        "ssh_key_href" => "/api/clouds/1/ssh_keys/B393T34EO2K90",
        "security_group_hrefs" => ["/api/clouds/1/security_groups/7OSUUQ36RMKOP"],
        "server_template_href" => "/api/server_templates/341896004"
      }
    }
    concurrent foreach $qty in $qty_ary do
      $$params["name"] = "foo-"+to_s($qty)
      # Change other things like inputs here
      @resource_definition = {"namespace": "rs", "type": "servers", "fields": $$params}
      # Should this actually be
      # $resource_definition = {"namespace": "rs", "type": "servers", "fields": $$parms}
      # @resource_definition = $resource_definition
      provision(@resource_definition)
    end
  end

  if $method_param == "realraw"
    $$params = {
      "server" => {
        "deployment_href" => @@deployment.href,
        "instance" => {
          "cloud_href" => "/api/clouds/1",
          "ssh_key_href" => "/api/clouds/1/ssh_keys/B393T34EO2K90",
          "security_group_hrefs" => ["/api/clouds/1/security_groups/7OSUUQ36RMKOP"],
          "server_template_href" => "/api/server_templates/341896004"
        }
      }
    }
    concurrent foreach $qty in $qty_ary do
      $$params["server"]["name"] = "foo-"+to_s($qty)
      # Change other things like inputs here
      @server = rs.servers.create($$params)
      @server.launch()
      sleep_while(@server.state != "operational")
    end
  end
end
