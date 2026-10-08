import os 
import zipfile 
from dotenv import load_dotenv

# 1. LOAD THE CREDENTIALS FIRST
load_dotenv() 

# 2. THEN IMPORT KAGGLE
from kaggle.api.kaggle_api_extended import KaggleApi


def download_wwi_dataset(download_path='./data'):
    if not os.path.exists(download_path):
        os.makedirs(download_path)

    if len(os.listdir(download_path)) > 0:
        print("Dataset already downloaded. Skipping download.")
        return
    print("Authenticating with Kaggle...")
    api = KaggleApi()
    api.authenticate()

    dataset_name = "pauloviniciusornelas/wwimporters"
    print(f"Downloading dataset '{dataset_name}'...")
    api.dataset_download_files(dataset_name, path=download_path, unzip=True)
    print("Download and extraction complete!")

if __name__ == "__main__":
    download_wwi_dataset()