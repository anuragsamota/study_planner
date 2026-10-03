FROM python:3.12-slim
WORKDIR /srv
COPY pyproject.toml ./
COPY study_planner_mcp ./study_planner_mcp
RUN pip install --no-cache-dir "mcp>=1.20,<2" "uvicorn>=0.30" "starlette>=0.40"
ENV PLANNER_DATA_DIR=/data PLANNER_HOST=0.0.0.0 PLANNER_PORT=8765
VOLUME ["/data"]
EXPOSE 8765
HEALTHCHECK CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8765/health')"
CMD ["python", "-m", "study_planner_mcp"]
