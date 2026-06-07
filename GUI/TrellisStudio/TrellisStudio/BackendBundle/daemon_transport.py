"""JSON response transport and tqdm progress patching."""

import json
import sys
import threading


_active_client_send = None
_send_lock = threading.Lock()


def send_response(data):
    """Send a JSON response to the active client, or stdout before connect."""
    with _send_lock:
        send = _active_client_send
    if send:
        send(data)
        return
    print(json.dumps({"response": data}))
    sys.stdout.flush()


class PatchedTqdm:
    """Small tqdm replacement that forwards known TRELLIS stages to Swift."""

    _lock = None

    def __init__(self, iterable=None, desc=None, disable=False, *args, **kwargs):
        self.iterable = iterable
        self.desc = desc
        self.disable = disable
        if iterable is not None:
            try:
                self.total = len(iterable)
            except Exception:
                self.total = kwargs.get("total", 0)
        else:
            self.total = kwargs.get("total", 0)
        self.current = 0
        self.n = 0
        self.pos = 0
        self.stage = self._stage_for_desc(desc)
        self._emit_progress()

    def __iter__(self):
        if self.iterable is None:
            return
        for item in self.iterable:
            yield item
            self.current += 1
            self.n = self.current
            self._emit_progress()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def update(self, n=1):
        self.current += n
        self.n = self.current
        self._emit_progress()

    def close(self):
        pass

    def clear(self, *args, **kwargs):
        pass

    def refresh(self, *args, **kwargs):
        pass

    def set_description(self, desc=None, refresh=True):
        self.desc = desc
        self.stage = self._stage_for_desc(desc)

    def set_postfix(self, *args, **kwargs):
        pass

    @classmethod
    def set_lock(cls, lock):
        cls._lock = lock

    @classmethod
    def get_lock(cls):
        if cls._lock is None:
            import threading as _threading
            cls._lock = _threading.RLock()
        return cls._lock

    @classmethod
    def write(cls, s, file=None, end="\n", nolock=False):
        pass

    @classmethod
    def external_write_mode(cls, *args, **kwargs):
        import contextlib
        return contextlib.nullcontext()

    @classmethod
    def pandas(cls, *args, **kwargs):
        raise NotImplementedError("PatchedTqdm does not support pandas")

    def _emit_progress(self):
        if self.disable or self.stage == "unknown":
            return
        send_response({
            "stage": self.stage,
            "status": "step",
            "current": self.current,
            "total": self.total,
            "message": self.desc or self.stage,
        })

    @staticmethod
    def _stage_for_desc(desc):
        desc_lower = (desc or "").lower()
        if "loading weights" in desc_lower:
            return "loadingPipeline"
        if "sparse structure" in desc_lower:
            return "samplingStructure"
        if "shape slat" in desc_lower:
            return "samplingShape"
        if "texture slat" in desc_lower:
            return "samplingTexture"
        return "unknown"


def apply_tqdm_patch():
    """Monkey-patch tqdm before TRELLIS modules import it."""
    import tqdm
    tqdm.tqdm = PatchedTqdm
    try:
        import tqdm.auto
        tqdm.auto.tqdm = PatchedTqdm
    except Exception:
        pass


apply_tqdm_patch()
