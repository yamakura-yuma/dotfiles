---
runs: 2
model: sonnet
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

/pstack:poteto-mode このリトライ処理、過剰設計になってない？もっと単純にできるなら直して。

```python
class RetryPolicy:
    def __init__(self, attempts=3, delay=0.5, backoff=1.0):
        self.attempts, self.delay, self.backoff = attempts, delay, backoff
class Retrier:
    def __init__(self, policy: RetryPolicy):
        self.policy = policy
    def run(self, fn):
        import time
        d = self.policy.delay
        for i in range(self.policy.attempts):
            try:
                return fn()
            except OSError:
                if i == self.policy.attempts - 1:
                    raise
                time.sleep(d); d *= self.policy.backoff
```
