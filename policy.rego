package envoy.authz

import rego.v1 

import input.attributes.request.http as http_attr

default allow := true

allow = response if {
    is_ratelimited
    response := {
      "allowed": false,
      "http_status": 429,
      "body": "Rate limited"
    }
}
allow = response if {
    needs_payment 
    response := {
      "allowed": false,
      "http_status": 402,
      "body": "Limits hit, payment needed"
    }
}
allow = response if {
    1 == 2
    response := {
      "allowed": false,
      "http_status": 503,
      "body": "Maintenance ongoing, please come back later"
    }
}

is_ratelimited if {
  env    := opa.runtime()["env"]
  base   := env["METRICS_SERVICE_HOST"]
  baseport := env["METRICS_SERVICE_PORT"]
  uri := sprintf("http://%v:%v/", [base, baseport])
  rate := http.send({"method":"GET", "url":uri, "body": input,
                     "headers": {"Content-Type":"application/json"},
                     "tls_insecure_skip_verify": true,
                     })
  rate.status_code == 429
}

needs_payment if {
  env    := opa.runtime()["env"]
  base   := env["METRICS_SERVICE_HOST"]
  baseport := env["METRICS_SERVICE_PORT"]
  uri := sprintf("http://%v:%v/payment", [base, baseport])
  rate := http.send({"method":"GET", "url":uri, "body": input,
                     "headers": {"Content-Type":"application/json"},
                     "tls_insecure_skip_verify": true,
                     })
  rate.status_code == 402
}

