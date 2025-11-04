# Example creating URL Map using terraform https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.9.0"
    }
  }
}

# Creates a target http proxy and global forwarding rule
resource "google_compute_target_http_proxy" "example" {
  name    = "example-proxy"
  url_map = google_compute_url_map.urlmap.id
  project = "gregbray-vpc"
}
resource "google_compute_global_forwarding_rule" "example" {
  name                  = "example-fwd-rule"
  target                = google_compute_target_http_proxy.example.id
  load_balancing_scheme = "EXTERNAL_MANAGED" # required when using route_rules. "EXTERNAL" aka Classic ALB only supports path_rule
  port_range            = "80"
  project               = "gregbray-vpc"
}

# Creates a URL Map. Full SDK docs at https://cloud.google.com/compute/docs/reference/rest/v1/urlMaps
resource "google_compute_url_map" "urlmap" {
  name        = "myurlmap"
  description = "a description"
  project     = "gregbray-vpc"
  #default_service = data.google_compute_backend_service.bes2.id  # instead use default_url_redirect to generate a redirect if no host_rule match
  #default_service = "https://www.googleapis.com/compute/v1/projects/gregbray-vpc/global/backendServices/gke-sa-bes2"  # instead of datasources or resources can also use static strings for backends

  # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_default_route_action
  # This is only for requests that don't match any host_rule sections below 
  #default_route_action {
  #  weighted_backend_services {
  #    backend_service = data.google_compute_backend_service.bes2.id
  #    weight          = 100
  #    header_action {
  #      request_headers_to_add {
  #        header_name  = "x-default-request"
  #        header_value = "true"
  #        replace      = true
  #      }
  #      response_headers_to_add {
  #        header_name  = "x-default-response"
  #        header_value = "true"
  #      }
  #    }
  #  }
  #}

  # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_default_url_redirect
  # instead of default action use a redirect if it doesn't match any of the below host rules
  default_url_redirect {
    host_redirect          = "example.com"
    path_redirect          = "/matched-default"
    strip_query            = false
    redirect_response_code = "SEE_OTHER"
  }

  # basic path_rule for example.net requests (can't mix/match inside path_matcher but can have some hosts with path_rule and other hosts with route_rules)
  host_rule {
    hosts        = ["example.net", "www.example.net"]  # this will not match any other subdomains. Use "*" to match all Host header domain values
    path_matcher = "all-net-paths"
  }
  # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher
  path_matcher {
    name        = "all-net-paths"
    description = "example of a basic path_rule config for example.net"

    # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher_path_matcher_route_rules_route_rules_route_action_weighted_backend_services_weighted_backend_services_header_action
    header_action {
      request_headers_to_add {
        header_name  = "x-request-test"
        header_value = "all-net-paths"
        replace      = true
      }
      response_headers_to_add {
        header_name  = "x-response-test"
        header_value = "all-net-paths"
        replace      = false
      }
    }

    # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher_path_matcher_path_rule
    path_rule {
      paths   = ["/app1"]   # longest path matching wins
      service = data.google_compute_backend_service.app1.id
    }
    path_rule {
      paths   = ["/app2"]
      service = data.google_compute_backend_service.app2.id
    }
    # path rules are always case sensitive matches, you have to use match_rules with ignoreCase for case insensitive matching

    # default used for any example.net requests that do not match above path rules
    default_route_action {
      # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher_path_matcher_route_rules_route_rules_route_action_cors_policy
      cors_policy {
        disabled = false            # Dynamically generate cors response headers from the LB
        #allow_headers = ["X-Custom-Header", "Upgrade-Insecure-Requests"]  # configures Access-Control-Allow-Headers header (not working?)
        #allow_credentials = true   # configures Access-Control-Allow-Credentials header (Defaults to false)        
        allow_methods = ["GET"]     # configures Access-Control-Allow-Methods header
        allow_origins = ["*"]       # configures Access-Control-Allow-Origin header
        #allow_origins = ["https://test.example.com", "http://test.example.com"] # HTTPS and HTTP for specific domain
        #allow_origin_regexes = [".*[.]example[.](com|org|net)"]    # Regular expressions can only be used when the loadBalancingScheme is set to INTERNAL_SELF_MANAGED        
        #expose_headers = ["*"]     # configures Access-Control-Expose-Headers header
        #max_age = 7200  # configures Access-Control-Max-Age header (not working?)
      }
      # test above using: curl -sv -H "Origin: http://test.example.com" -H "Access-Control-Request-Headers: x-custom-header" -H "host: example.net" http://34.160.67.42/asdf
      # but won't apply to /app1 or /app2 as those would need their own cors_policy section

      # For requests that don't match above paths, split them evenly across app1 and app2 backends
      weighted_backend_services {
        backend_service = data.google_compute_backend_service.app1.id
        weight          = 1
        header_action {
          request_headers_to_add {
            header_name  = "x-default-request"
            header_value = "true"
            replace      = true
          }
          response_headers_to_add {
            header_name  = "x-default-response"
            header_value = "true"
          }
        }
      }
      weighted_backend_services {
        backend_service = data.google_compute_backend_service.app2.id
        weight          = 1
        header_action {
          request_headers_to_add {
            header_name  = "x-default-request"
            header_value = "true"
            replace      = true
          }
          response_headers_to_add {
            header_name  = "x-default-response"
            header_value = "true"
          }
        }
      }
    }
  }



  # More complex routing using match_rules (not supported on Classic ALB)
  host_rule {
    hosts        = ["example.com", "*.example.com"]   # this includes all subdomains including foo.bar.example.com
    path_matcher = "all-com-paths"
  }
  path_matcher {
    name            = "all-com-paths"
    default_service = data.google_compute_backend_service.bes2.id

    # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher_path_matcher_route_rules
    route_rules {
      priority = 100  # lowest priority match wins
      service  = data.google_compute_backend_service.app1.id  # (or can define weighted_backend_services in route_action below)
      # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher_path_matcher_route_rules_route_rules_match_rules
      match_rules {
        prefix_match = "/one/"  # matches /one/ or /ONE/whatever but not /one (which would need it's own match_rules section)
        ignore_case  = true     # case-insensitive match
      }
      # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher_path_matcher_route_rules_route_rules_route_action
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/" # strip above matching prefix before forwarding request to backend
        }
        # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher_path_matcher_route_rules_route_rules_route_action_cors_policy
        cors_policy {
          disabled = false # Dynamically generate cors response headers from the LB
          allow_methods = ["GET"]   # configures Access-Control-Allow-Methods header
          allow_origins = ["*"]
        }
      }
      # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher_path_matcher_route_rules_route_rules_route_action_weighted_backend_services_weighted_backend_services_header_action
      header_action {
        request_headers_to_remove = ["x-remove-request"]
        request_headers_to_add {
          header_name  = "AddSomethingElse"
          header_value = "MyOtherValue"
          replace      = true
        }
        response_headers_to_remove = ["server", "x-real-server"]
        response_headers_to_add {
          header_name  = "x-response-test"
          header_value = "match-one"
          replace      = false
        }
      }
    }
    route_rules {
      priority = 200
      service  = data.google_compute_backend_service.app2.id
      match_rules {
        ignore_case  = false    # case-sensitive match
        prefix_match = "/two/"  # again this matches /two/ or /two/whatever but not /two
      }
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/" # strip matching prefix before forwarding to backend
        }
      }
      header_action {
        response_headers_to_add {
          header_name  = "x-real-server"
          header_value = "match-two"
          replace      = true
        }
      }
    }
    # https://cloud.google.com/load-balancing/docs/url-map-concepts#wildcards-regx-dynamic-route
    route_rules {
      priority = 300
      match_rules {
        path_template_match = "/template/{first=*}/test/{rest=**}"
      }
      service = data.google_compute_backend_service.bes2.id
      route_action {
        url_rewrite {
          path_template_rewrite = "/{first}-{rest}/"
        }
      }
    }
    route_rules {
      priority = 400
      match_rules {
        ignore_case  = true
        prefix_match = "/redirect" # matches /redirect and /redirectwhatever or /RedirectBlah/Blah
      }
      # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher_path_matcher_route_rules_route_rules_url_redirect
      url_redirect {
        host_redirect          = "example.com"
        path_redirect          = "/"
        https_redirect         = false
        redirect_response_code = "TEMPORARY_REDIRECT"
        strip_query            = true
      }
    }
    # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map#nested_path_matcher_path_matcher_path_rule_path_rule_route_action_weighted_backend_services
    route_rules {
      priority = 500
      match_rules {
        ignore_case  = true
        prefix_match = "/canary"
      }
      route_action {
        # route canary traffic across app1 and app2 backends at 9 to 1 ratio 
        weighted_backend_services {
          backend_service = data.google_compute_backend_service.app1.id
          weight          = 90
        }
        weighted_backend_services {
          backend_service = data.google_compute_backend_service.app2.id
          weight          = 10
        }
      }
      header_action {
        response_headers_to_add {
          header_name  = "x-testing"
          header_value = "canary"
          replace      = true
        }
      }
    }
  }

  test {
    service = data.google_compute_backend_service.app1.id
    host    = "example.com"
    path    = "/one/"
  }
}

# Instead of creating backend services as resources here this example just uses datasources to reference pre-existing backends
data "google_compute_backend_service" "bes" {
  name    = "gke-sa-bes"
  project = "gregbray-vpc"
}

data "google_compute_backend_service" "bes2" {
  name    = "gke-sa-bes2"
  project = "gregbray-vpc"
}

# These are backends managed by GKE. Their names could change so you should create standalone NEGs instead
data "google_compute_backend_service" "app1" {
  name    = "gkegw1-s6d4-app-1-whereami-80-d3zrao4p3b1p"
  project = "gregbray-vpc"
}
data "google_compute_backend_service" "app2" {
  name    = "gkegw1-s6d4-app-2-whereami-80-3gjwc9e6pii6"
  project = "gregbray-vpc"
}

# Reference to existing check that requires HTTP 200 response code for "/" https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_http_health_check
data "google_compute_health_check" "default" {
  name    = "http-basic-check"
  project = "gregbray-vpc"
}

/*
Trying to use advanced routing for gke-sa-bes which is a "Backend service (Classic)" aka --load-balancing-scheme EXTERNAL will generate an error:
google_compute_url_map.urlmap: Creating...
╷
│ Error: Error creating UrlMap: googleapi: Error 400: Invalid value for field 'resource.defaultService': 'https://compute.googleapis.com/compute/v1/projects/gregbray-vpc/global/backendServices/gke-sa-bes'.
|        Advanced routing rules are not supported for scheme EXTERNAL, invalid
│ 
│   with google_compute_url_map.urlmap,
│   on main.tf line 10, in resource "google_compute_url_map" "urlmap":
│   10: resource "google_compute_url_map" "urlmap" {
│ 

Need to use --load-balancing-scheme EXTERNAL_MANAGED backend services (not classic ALB)
For existing classic ALB your can migrate them using https://cloud.google.com/load-balancing/docs/https/migrate-to-global

Terraform commands:

terraform init
terraform plan
terraform apply -auto-aprove
*/
