import os
import unittest
from unittest import mock

import shop


class ShipOrderTest(unittest.TestCase):
    def test_marks_shipped_and_emails(self):
        with mock.patch.dict(os.environ, {"MAIL_API_URL": "http://mail.test/send"}), \
                mock.patch("urllib.request.urlopen") as urlopen:
            order = shop.ship_order({"id": 7, "email": "a@example.com", "status": "paid"})
        self.assertEqual(order["status"], "shipped")
        self.assertEqual(urlopen.call_args.args[0].full_url, "http://mail.test/send")


if __name__ == "__main__":
    unittest.main()
