import os, sys, unittest
sys.path.insert(0, os.getcwd())
import report
U = [
 {"id": 5, "name": "  éve  o'neil", "joined": "2022-02-28", "active": True, "plan": None},
 {"id": 4, "name": "dan", "joined": "2021-07-04", "active": True, "plan": "team"},
 {"id": 9, "name": "zed", "joined": "2020-01-01"},
 {"id": 1, "name": "amy, jr", "joined": "2024-10-10", "active": 1},
]
EXP_CSV = 'id,name,joined,plan\r\n1,"Amy, Jr",2024/10/10,free\r\n4,Dan,2021/07/04,team\r\n5,Éve  O\'Neil,2022/02/28,free\r\n'
EXP_JSON = '[\n  {\n    "id": 1,\n    "name": "Amy, Jr",\n    "joined": "2024/10/10",\n    "plan": "free"\n  },\n  {\n    "id": 4,\n    "name": "Dan",\n    "joined": "2021/07/04",\n    "plan": "team"\n  },\n  {\n    "id": 5,\n    "name": "Éve  O\'Neil",\n    "joined": "2022/02/28",\n    "plan": "free"\n  }\n]'
class Accept(unittest.TestCase):
    def test_csv(self): self.assertEqual(report.export_csv(U), EXP_CSV)
    def test_json(self): self.assertEqual(report.export_json(U), EXP_JSON)
    def test_empty(self):
        self.assertEqual(report.export_csv([]), "id,name,joined,plan\r\n")
        self.assertEqual(report.export_json([]), "[]")
unittest.main(argv=["x"], exit=True)
