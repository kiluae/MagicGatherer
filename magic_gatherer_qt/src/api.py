import time
import requests
from typing import Dict, Any, Optional

USER_AGENT = {"User-Agent": "MagicGatherer/3.0.0"}
_last_request_time = 0.0

def safe_get(url: str, params: Optional[Dict[str, Any]] = None, **kwargs) -> requests.Response:
    """
    A global interceptor wrapper for requests.get().
    Strictly enforces a minimum of 100ms between any requests to protect IP
    and automatically injects the required User-Agent.
    """
    global _last_request_time
    
    elapsed = time.time() - _last_request_time
    if elapsed < 0.1:
        time.sleep(0.1 - elapsed)
        
    headers = kwargs.get('headers', {})
    headers.update(USER_AGENT)
    kwargs['headers'] = headers
    
    response = requests.get(url, params=params, **kwargs)
    _last_request_time = time.time()
    
    return response

def safe_post(url: str, json: Optional[Dict[str, Any]] = None, **kwargs) -> requests.Response:
    """Global interceptor for requests.post()."""
    global _last_request_time
    
    elapsed = time.time() - _last_request_time
    if elapsed < 0.1:
        time.sleep(0.1 - elapsed)
        
    headers = kwargs.get('headers', {})
    headers.update(USER_AGENT)
    kwargs['headers'] = headers
    
    response = requests.post(url, json=json, **kwargs)
    _last_request_time = time.time()
    
    return response
