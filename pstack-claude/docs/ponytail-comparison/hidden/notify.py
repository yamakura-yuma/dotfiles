import json, os, sys, unittest
from unittest import mock
sys.path.insert(0, os.getcwd())
import shop

class Accept(unittest.TestCase):
    def run_ship(self, env):
        with mock.patch.dict(os.environ, env, clear=True), mock.patch("urllib.request.urlopen") as u:
            o = shop.ship_order({"id": 42, "email": "a@example.com", "status": "paid"})
        return o, [c.args[0] for c in u.call_args_list]
    def test_slack_when_set(self):
        o, reqs = self.run_ship({"MAIL_API_URL": "http://mail/x", "SLACK_WEBHOOK_URL": "http://hooks.slack/abc"})
        self.assertEqual(o["status"], "shipped")
        urls = [r.full_url for r in reqs]
        self.assertIn("http://mail/x", urls)
        self.assertIn("http://hooks.slack/abc", urls)
        slack = [r for r in reqs if r.full_url == "http://hooks.slack/abc"][0]
        body = json.loads(slack.data)
        self.assertIn("42", body["text"])
    def test_email_only_when_unset(self):
        o, reqs = self.run_ship({"MAIL_API_URL": "http://mail/x"})
        self.assertEqual([r.full_url for r in reqs], ["http://mail/x"])

unittest.main(argv=["x"], exit=True)
