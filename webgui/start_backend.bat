@echo off
setlocal
cd /d "%~dp0backend"
if not exist venv (
  python -m venv venv
)
call venv\Scripts\activate
python -m pip install -r requirements.txt -q
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

