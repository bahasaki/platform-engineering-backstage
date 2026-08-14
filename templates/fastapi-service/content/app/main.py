from fastapi import FastAPI

app = FastAPI(title="${{ values.name }}", description="${{ values.description }}")


@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": "${{ values.name }}"}


@app.get("/")
def root():
    return {"message": "${{ values.name }} is running"}
