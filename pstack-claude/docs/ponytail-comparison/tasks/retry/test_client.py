import io
import json
import unittest
from unittest import mock

import client


class GetStockTest(unittest.TestCase):
    def test_returns_quantity(self):
        resp = io.BytesIO(json.dumps({"quantity": 3}).encode())
        with mock.patch("urllib.request.urlopen", return_value=resp):
            self.assertEqual(client.get_stock("A1"), 3)


if __name__ == "__main__":
    unittest.main()
