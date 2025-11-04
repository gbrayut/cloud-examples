

 /*, /foo/*, and /foo/bar/* are valid patterns, but *, /foo/bar*, and /foo/*/bar are not.

A more specific pattern takes precedence over a less specific pattern. If you have both /foo/* and /foo/bar/*, then /foo/bar/bat is taken to match /foo/bar/*.

URL Maps documentation


old guide for nginx https://github.com/GoogleCloudPlatform/community/blob/master/archived/nginx-ingress-gke/index.md 

---

nginx CRDs for cross namespace https://docs.nginx.com/nginx-ingress-controller/configuration/ingress-resources/cross-namespace-configuration/



---

https://cloud.google.com/kubernetes-engine/docs/concepts/ingress-xlb#support_for_websocket


curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Host: echo.websocket.org" -H "Origin: https://www.websocket.org" https://echo.websocket.org


kubectl create ns echo

export myport=8080;kubectl run -n echo --env="PORT=$myport" --image=docker.io/inanimate/echo-server --port ${myport} --expose echo${myport}

export myport=9090;kubectl run -n echo --env="PORT=$myport" --image=docker.io/inanimate/echo-server --port ${myport} --expose echo${myport}

kubectl port-forward -n echo service/echo8080 18080:8080








path	<string>
    path is matched against the path of an incoming request. Currently it can
    contain characters disallowed from the conventional "path" part of a URL as
    defined by RFC 3986. Paths must begin with a '/' and must be present when
    using PathType with value "Exact" or "Prefix".

  pathType	<string> -required-
    pathType determines the interpretation of the path matching. PathType can be
    one of the following values: * Exact: Matches the URL path exactly. *
    Prefix: Matches based on a URL path prefix split by '/'. Matching is
      done on a path element by element basis. A path element refers is the
      list of labels in the path split by the '/' separator. A request is a
      match for path p if every p is an element-wise prefix of p of the
      request path. Note that if the last element of the path is a substring
      of the last element in request path, it is not a match (e.g. /foo/bar
      matches /foo/bar/baz, but does not match /foo/barbaz).
    * ImplementationSpecific: Interpretation of the Path matching is up to
      the IngressClass. Implementations can treat this as a separate PathType
      or treat it identically to Prefix or Exact path types.
    Implementations are required to support all path types.
    
    Possible enum values:
     - `"Exact"` matches the URL path exactly and with case sensitivity.
     - `"ImplementationSpecific"` matching is up to the IngressClass.
    Implementations can treat this as a separate PathType or treat it
    identically to Prefix or Exact path types.
     - `"Prefix"` matches based on a URL path prefix split by '/'. Matching is
    case sensitive and done on a path element by element basis. A path element
    refers to the list of labels in the path split by the '/' separator. A
    request is a match for path p if every p is an element-wise prefix of p of
    the request path. Note that if the last element of the path is a substring
    of the last element in request path, it is not a match (e.g. /foo/bar
    matches /foo/bar/baz, but does not match /foo/barbaz). If multiple matching
    paths exist in an Ingress spec, the longest matching path is given priority.
    Examples: - /foo/bar does not match requests to /foo/barbaz - /foo/bar
    matches request to /foo/bar and /foo/bar/baz - /foo and /foo/ both match
    requests to /foo and /foo/. If both paths are present in an Ingress spec,
    the longest matching path (/foo/) is given priority.
