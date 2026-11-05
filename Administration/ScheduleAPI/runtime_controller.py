from __future__ import annotations

from copy import deepcopy
from threading import RLock, Thread
from typing import Any, Callable


class RuntimeController:
    def __init__(self) -> None:
        self._lock = RLock()
        self._thread: Thread | None = None
        self._settings = {
            "concurrent_operation_sets": 10,
            "operations_per_set": 200,
            "polling_wait_seconds": 30,
            "authorization_expires_at": 0.0,
        }
        self._state: dict[str, Any] = {
            "running": False,
            "finished": False,
            "stop_requested": False,
            "stopped": False,
            "error": "",
            "logs": [],
            "execution_records": [],
            "outcomes": [],
            "executed_v3_payloads": [],
            "executed_v3_responses": [],
        }

    def update_settings(
        self,
        *,
        concurrent_operation_sets: int,
        operations_per_set: int,
        polling_wait_seconds: int,
        authorization_expires_at: float = 0.0,
    ) -> None:
        if not 1 <= concurrent_operation_sets <= 10:
            raise ValueError("Concurrent operation sets must be between 1 and 10.")
        if not 1 <= operations_per_set <= 200:
            raise ValueError("Operations per set must be between 1 and 200.")
        if polling_wait_seconds < 1:
            raise ValueError("Polling wait time must be greater than 0 seconds.")
        with self._lock:
            self._settings = {
                "concurrent_operation_sets": concurrent_operation_sets,
                "operations_per_set": operations_per_set,
                "polling_wait_seconds": polling_wait_seconds,
                "authorization_expires_at": authorization_expires_at,
            }

    def settings(self) -> dict[str, int | float]:
        with self._lock:
            return dict(self._settings)

    def add_log(self, message: str) -> None:
        with self._lock:
            self._state["logs"].append(message)

    def logs(self) -> list[str]:
        with self._lock:
            return list(self._state["logs"])

    def set_execution_records(self, records: list[dict[str, Any]]) -> None:
        with self._lock:
            self._state["execution_records"] = records

    def request_stop(self) -> None:
        with self._lock:
            if self._state["running"]:
                self._state["stop_requested"] = True

    def stop_requested(self) -> bool:
        with self._lock:
            return bool(self._state["stop_requested"])

    def reset(self) -> None:
        with self._lock:
            if self._state["running"]:
                raise RuntimeError(
                    "Cannot replace the input file while an upload is running."
                )
            self._state = {
                "running": False,
                "finished": False,
                "stop_requested": False,
                "stopped": False,
                "error": "",
                "logs": [],
                "execution_records": [],
                "outcomes": [],
                "executed_v3_payloads": [],
                "executed_v3_responses": [],
            }

    def restore(
        self,
        *,
        logs: list[str],
        execution_records: list[dict[str, Any]],
    ) -> None:
        with self._lock:
            if self._state["running"]:
                return
            self._state["logs"] = list(logs)
            self._state["execution_records"] = execution_records
            self._state["finished"] = False
            self._state["error"] = ""

    def start(
        self,
        target: Callable[[RuntimeController], dict[str, Any]],
        *,
        preserve_state: bool = False,
    ) -> None:
        with self._lock:
            if self._state["running"]:
                raise RuntimeError("An upload is already running.")
            if preserve_state:
                self._state["running"] = True
                self._state["finished"] = False
                self._state["stop_requested"] = False
                self._state["stopped"] = False
                self._state["error"] = ""
            else:
                self._state = {
                    "running": True,
                    "finished": False,
                    "stop_requested": False,
                    "stopped": False,
                    "error": "",
                    "logs": [],
                    "execution_records": [],
                    "outcomes": [],
                    "executed_v3_payloads": [],
                    "executed_v3_responses": [],
                }

        def run() -> None:
            try:
                result = target(self)
            except Exception as exc:  # noqa: BLE001
                with self._lock:
                    self._state["error"] = str(exc)
            else:
                with self._lock:
                    self._state.update(result)
            finally:
                with self._lock:
                    self._state["running"] = False
                    self._state["finished"] = True

        self._thread = Thread(target=run, name="schedule-upload", daemon=True)
        self._thread.start()

    def snapshot(self) -> dict[str, Any]:
        for attempt in range(10):
            try:
                with self._lock:
                    return deepcopy({**self._state, "settings": self._settings})
            except RuntimeError as exc:
                if "changed size during iteration" not in str(exc) or attempt == 9:
                    raise
        raise RuntimeError("Could not capture runtime state.")