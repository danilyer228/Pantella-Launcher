@echo off
echo Reinstalling torch with only CPU support
"%~dp0\python-3.10.11-embed\python.exe" -m pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 --no-deps --no-cache-dir --force-reinstall --upgrade
echo Done