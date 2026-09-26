import io, json, os, socket, sys, unittest, urllib.error
from unittest import mock
sys.path.insert(0, os.getcwd())
import client
def ok(): return io.BytesIO(json.dumps({"quantity": 7}).encode())
def http(code): return urllib.error.HTTPError("u", code, "x", {}, None)
class Accept(unittest.TestCase):
    def call(self, effects):
        with mock.patch("urllib.request.urlopen", side_effect=effects) as u, mock.patch("time.sleep"):
            try: return client.get_stock("A1"), u.call_count, None
            except Exception as e: return None, u.call_count, e
    def test_5xx_then_ok(self):
        r, n, e = self.call([http(503), http(502), ok()]); self.assertEqual((r, n, e), (7, 3, None))
    def test_timeout_then_ok(self):
        r, n, e = self.call([socket.timeout("t"), ok()]); self.assertEqual((r, n), (7, 2))
    def test_urlerror_then_ok(self):
        r, n, e = self.call([urllib.error.URLError("refused"), ok()]); self.assertEqual((r, n), (7, 2))
    def test_4xx_not_retried(self):
        r, n, e = self.call([http(404), ok()]); self.assertEqual(n, 1); self.assertIsInstance(e, urllib.error.HTTPError)
    def test_gives_up_after_3(self):
        r, n, e = self.call([http(500), http(500), http(500), ok()]); self.assertEqual(n, 3); self.assertIsInstance(e, urllib.error.HTTPError); self.assertEqual(e.code, 500)
unittest.main(argv=["x"], exit=True)
