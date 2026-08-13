Since Windows doesn't run bash scripts natively, the easiest way to get that Mini Fog image on Windows is to run the build script using WSL, Windows Subsystem for Linux, which you can install from your PowerShell.
Once you've built the image and transferred it to your Windows desktop, you can flash it directly to your USB drive using Rufus, selecting the "DD" mode to ensure the partition structure is written correctly.

While you can use Git Bash on Windows to download the files, building the actual disk image requires a Linux-like environment with low-level system tools like parted and losetup.
The best way to do this on Windows is to use WSL, the Windows Subsystem for Linux, which you can install from your PowerShell. Once that's set up, you can open the Ubuntu terminal, run your build script, and generate the image right there.

Installing WSL (Windows Subsystem for Linux) via PowerShell is straightforward and takes just a couple of steps. Here is how to do it from start to finish:
Step 1: Open PowerShell as Administrator
 * Click on your Windows Start Menu (or press the Windows key).
 * Type PowerShell.
 * Right-click on Windows PowerShell and select Run as administrator.
 * Click Yes if Windows asks for permission (UAC prompt).
Step 2: Run the Install Command
In the blue PowerShell window, type the following command and press Enter:
wsl --install

> What this does: This single command enables the necessary Windows features, downloads the Linux kernel, and installs Ubuntu as your default Linux environment.
> 
Step 3: Restart Your Computer
Once the process finishes downloading, restart your PC so Windows can apply the changes:
shutdown /r /t 0

(Or simply restart via your Start menu as usual).
Step 4: Set Up Your Linux Username and Password
 * After your PC restarts, a new black terminal window (Ubuntu) will open automatically. (If it doesn't, search for Ubuntu in your Start menu and click it).
 * Wait a minute or two while it finishes the initial setup.
 * It will ask you to:
   * Enter new UNIX username: Type a simple name (e.g., admin or your first name) and hit Enter.
   * New password: Type a password and press Enter.
   > Note: The cursor will NOT move or show characters while you type your password. This is normal security behavior—just type it out and hit Enter.
   > 
Step 5: Build Your Image
Now you have a full Linux terminal running inside Windows! You can clone your repository and build your image:
# 1. Update package list
sudo apt update && sudo apt install -y git

# 2. Clone your Git repository
git clone <YOUR_GIT_REPO_URL>
cd <YOUR_REPO_DIRECTORY>

# 3. Run your build script
sudo ./make_mini_live_img.sh

Once built, your berry-mini-fork.img file will be located inside that Linux folder. You can easily access it from Windows Explorer by typing \\wsl$ in your Windows file address bar!
