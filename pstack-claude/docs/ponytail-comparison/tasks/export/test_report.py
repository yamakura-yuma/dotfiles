import json
import unittest

import report

USERS = [
    {"id": 2, "name": " bob smith ", "joined": "2024-03-05", "active": True},
    {"id": 1, "name": "alice", "joined": "2023-12-31", "active": True, "plan": "pro"},
    {"id": 3, "name": "carol", "joined": "2024-01-01", "active": False},
]


class ReportTest(unittest.TestCase):
    def test_csv(self):
        self.assertEqual(
            report.export_csv(USERS),
            "id,name,joined,plan\r\n1,Alice,2023/12/31,pro\r\n2,Bob Smith,2024/03/05,free\r\n",
        )

    def test_json(self):
        self.assertEqual([r["id"] for r in json.loads(report.export_json(USERS))], [1, 2])


if __name__ == "__main__":
    unittest.main()
