"""Upload local files to the SeaweedFS S3-compatible API."""

from __future__ import annotations

import argparse
import mimetypes
import os
from pathlib import Path

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError


DEFAULT_ENDPOINT = "http://localhost:8333"
DEFAULT_BUCKET = "data-lake"


def build_s3_client(endpoint: str):
    """Create an S3 client configured for SeaweedFS."""
    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID", "admin"),
        aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY", "admin"),
        region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"),
        config=Config(s3={"addressing_style": "path"}),
    )


def ensure_bucket(client, bucket: str) -> None:
    """Create the destination bucket when it does not exist."""
    try:
        client.head_bucket(Bucket=bucket)
    except ClientError as error:
        error_code = error.response.get("Error", {}).get("Code")
        if error_code not in {"404", "NoSuchBucket"}:
            raise
        client.create_bucket(Bucket=bucket)


def files_to_upload(source: Path) -> list[tuple[Path, str]]:
    """Return files and their paths relative to the upload source."""
    if source.is_file():
        return [(source, source.name)]
    if source.is_dir():
        return [
            (path, path.relative_to(source).as_posix())
            for path in sorted(source.rglob("*"))
            if path.is_file()
        ]
    raise FileNotFoundError(f"Upload source does not exist: {source}")


def upload_files(
    client,
    source: Path,
    bucket: str,
    prefix: str = "",
) -> int:
    """Upload a file or every file below a directory and return the count."""
    uploaded = 0
    normalized_prefix = prefix.strip("/")
    for path, relative_key in files_to_upload(source):
        key = "/".join(part for part in (normalized_prefix, relative_key) if part)
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        client.upload_file(
            str(path),
            bucket,
            key,
            ExtraArgs={"ContentType": content_type},
        )
        print(f"Uploaded {path} -> s3://{bucket}/{key}")
        uploaded += 1
    return uploaded


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Upload a file or directory to SeaweedFS through its S3 API."
    )
    parser.add_argument(
        "source",
        nargs="?",
        type=Path,
        default=Path("data"),
        help="File or directory to upload (default: data)",
    )
    parser.add_argument(
        "--endpoint",
        default=os.getenv("SEAWEEDFS_ENDPOINT", DEFAULT_ENDPOINT),
        help=f"SeaweedFS S3 endpoint (default: {DEFAULT_ENDPOINT})",
    )
    parser.add_argument(
        "--bucket",
        default=os.getenv("SEAWEEDFS_BUCKET", DEFAULT_BUCKET),
        help=f"Destination bucket (default: {DEFAULT_BUCKET})",
    )
    parser.add_argument(
        "--prefix",
        default=os.getenv("SEAWEEDFS_PREFIX", ""),
        help="Optional key prefix inside the bucket",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    client = build_s3_client(args.endpoint)
    ensure_bucket(client, args.bucket)
    count = upload_files(client, args.source, args.bucket, args.prefix)
    print(f"Uploaded {count} file(s) to s3://{args.bucket}")


if __name__ == "__main__":
    main()
