# casestudy1

## Upload files to SeaweedFS

Start SeaweedFS with Docker Compose:

```powershell
docker compose up -d seaweedfs
```

The uploader uses SeaweedFS's S3-compatible API at `http://localhost:8333`.
With the default command, it recursively uploads the local `data` directory
to a bucket named `data-lake`:

```powershell
.\venv\Scripts\python.exe scripts\ingest.py
```

Upload a different directory, bucket, or key prefix with:

```powershell
.\venv\Scripts\python.exe scripts\ingest.py data\Sales --bucket sales --prefix raw
```

The endpoint and bucket can also be configured with `SEAWEEDFS_ENDPOINT` and
`SEAWEEDFS_BUCKET`. If your SeaweedFS deployment requires credentials, set
`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` before running the script.