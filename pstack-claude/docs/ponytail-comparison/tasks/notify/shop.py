import json
import os
import urllib.request


def send_email(to, subject, body):
    req = urllib.request.Request(
        os.environ["MAIL_API_URL"],
        data=json.dumps({"to": to, "subject": subject, "body": body}).encode(),
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req, timeout=10)


def ship_order(order):
    order["status"] = "shipped"
    send_email(
        order["email"],
        f"Order {order['id']} shipped",
        f"Your order {order['id']} is on its way.",
    )
    return order
