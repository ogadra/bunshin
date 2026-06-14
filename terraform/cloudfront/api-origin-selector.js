import cf from 'cloudfront';

function hashString(value) {
  var hash = 2166136261;

  for (var i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }

  return hash >>> 0;
}

function routingKey(event) {
  var request = event.request;

  if (request.cookies && request.cookies.session_id && request.cookies.session_id.value) {
    return request.cookies.session_id.value;
  }

  if (event.viewer && event.viewer.ip) {
    return event.viewer.ip;
  }

  return request.uri;
}

function handler(event) {
  var originId = hashString(routingKey(event)) % 2 === 0 ? 'api-ingress-apne1' : 'api-ingress-apne3';

  cf.selectRequestOriginById(originId);

  return event.request;
}
