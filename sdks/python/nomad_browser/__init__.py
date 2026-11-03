"""
Nomad Browser Python SDK
High-speed, native macOS agentic browser driver and CDP bridge.
"""

import json
import os
import subprocess
import urllib.request
import urllib.error
from typing import Optional, Dict, Any, List

__version__ = "0.30.0"

class Nomad:
    """
    Client for interacting with Nomad's embedded agent server and native WebKit engine.
    """

    def __init__(self, port: int = 9222, host: str = "127.0.0.1", token: Optional[str] = None):
        self.port = port
        self.host = host
        self.base_url = f"http://{host}:{port}"
        self.cdp_url = self.base_url
        self.token = token or self._load_token()

    @staticmethod
    def _load_token() -> str:
        env = os.environ.get("NOMAD_TOKEN")
        if env:
            return env.strip()
        token_path = os.path.expanduser("~/.nomad/agent-token")
        if os.path.exists(token_path):
            with open(token_path, "r", encoding="utf-8") as f:
                return f.read().strip()
        return ""

    @classmethod
    def start_worker(cls, profile: str = "agent", idle_timeout: int = 60, port: Optional[int] = None) -> "Nomad":
        """Spins up a headless Nomad worker process and returns a connected client."""
        cmd = ["nomad", "start", "--profile", profile, "--idle-timeout", str(idle_timeout)]
        if port:
            cmd.extend(["--port", str(port)])
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        # Parse port from output if dynamic
        for line in res.stdout.splitlines():
            if "HTTP: http://127.0.0.1:" in line:
                p = int(line.split(":")[-1].strip())
                return cls(port=p)
        return cls(port=port or 9222)

    def _request(self, method: str, path: str, data: Optional[Dict[str, Any]] = None) -> Any:
        url = f"{self.base_url}{path}"
        headers = {
            "Content-Type": "application/json"
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        body = json.dumps(data).encode("utf-8") if data else None
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                content = resp.read().decode("utf-8")
                if not content:
                    return None
                return json.loads(content)
        except urllib.error.HTTPError as e:
            err_body = e.read().decode("utf-8")
            raise RuntimeError(f"Nomad HTTP {e.code}: {err_body}")

    def status(self) -> Dict[str, Any]:
        """Returns browser and worker status."""
        return self._request("GET", "/status")

    def cdp_version(self) -> Dict[str, Any]:
        """Returns Chrome DevTools Protocol version declaration."""
        return self._request("GET", "/json/version")

    def tabs(self) -> List[Dict[str, Any]]:
        """Lists active tabs."""
        res = self._request("GET", "/tabs")
        return res.get("tabs", [])

    def new_tab(self, url: Optional[str] = None) -> Dict[str, Any]:
        """Creates a new browser tab."""
        return self._request("POST", "/tabs/new", {"url": url} if url else {})

    def navigate(self, url: str) -> Dict[str, Any]:
        """Navigates the active tab to a URL."""
        return self._request("POST", "/navigate", {"url": url})

    def snapshot(self, mode: str = "text", limit: int = 50) -> Dict[str, Any]:
        """Captures a token-optimized semantic tree snapshot."""
        return self._request("GET", f"/snapshot?mode={mode}&limit={limit}")

    def click(self, target: str, native: bool = True) -> Dict[str, Any]:
        """Clicks an element by reference (e.g. 'e1') or selector."""
        return self._request("POST", "/action", {"action": "click", "target": target, "native": native})

    def type(self, target: str, text: str, submit: bool = False, native: bool = True) -> Dict[str, Any]:
        """Types text into an element."""
        return self._request("POST", "/action", {"action": "type", "target": target, "text": text, "submit": submit, "native": native})

    def evaluate(self, expression: str) -> Any:
        """Evaluates JavaScript in the active tab."""
        res = self._request("POST", "/evaluate", {"expression": expression})
        return res.get("result")

