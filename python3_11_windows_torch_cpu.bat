@echo off
echo Reinstalling torch with only CPU support
"%~dp0\python-3.11.6-embed\python.exe" -m pip install torch torchvision torchaudio --no-deps --no-cache-dir --force-reinstall --upgrade
echo Done