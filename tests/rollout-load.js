// Step 28 - zero-downtime proof. Constant traffic through the ALB while the cluster
// rolls pods (rollout restart) and drains a node. Pass = zero failed requests.
//
//   BASE_URL=http://<alb-dns> JWT=<token> k6 run tests/rollout-load.js
//
// Mix: /health (DB ping) + POST /evaluate (auth + cache/DB). Constant arrival rate, so a
// slow or refused request cannot silently reduce the request count.
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL;
const AUTH = { headers: { Authorization: `Bearer ${__ENV.JWT}`, 'Content-Type': 'application/json' } };

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RPS || 20), timeUnit: '1s',
      duration: __ENV.DURATION || '6m',
      preAllocatedVUs: 20, maxVUs: 100,
    },
  },
  thresholds: {
    http_req_failed: ['rate==0'],        // the claim: not a single failed request
    'http_req_duration{expected_response:true}': ['p(95)<500'],
  },
};

export default function () {
  const r1 = http.get(`${BASE}/health`, { tags: { ep: 'health' } });
  check(r1, { 'health 200': (r) => r.status === 200 });
  const r2 = http.post(`${BASE}/evaluate`,
    JSON.stringify({ flag_name: 'rollout-test', user_id: `u${__ITER % 1000}`, environment: 'dev' }),
    Object.assign({ tags: { ep: 'evaluate' } }, AUTH));
  check(r2, { 'evaluate 200': (r) => r.status === 200 });
}
