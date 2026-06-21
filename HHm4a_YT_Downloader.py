import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import yt_dlp
import threading
import os
import re
import string
import sys
import warnings
import logging

# ----------------------
# Configuration
# ----------------------

STANDARD_HEIGHTS = [
    (2160, "4k"),
    (1440, "2k"),
    (1080, "1080p"),
    (720,  "720p"),
    (480,  "480p"),
    (360,  "360p"),
    (240,  "240p"),
    (144,  "144p"),
]

# ----------------------
# Silence logs and warnings
# ----------------------

warnings.filterwarnings("ignore")
logging.getLogger().setLevel(logging.WARNING)

class SilentLogger:
    def debug(self, msg): pass
    def info(self, msg): pass
    def warning(self, msg): pass
    def error(self, msg): pass

# ----------------------
# Helpers
# ----------------------

def is_valid_youtube_url(url):
    pattern = r"(https?://)?(www\.)?(youtube\.com|youtu\.be)/.+"
    return bool(re.match(pattern, url))

def estimate_mp3_size(duration, kbps):
    try:
        return round(duration * kbps * 1000 / 8 / 1024 / 1024, 2)
    except Exception:
        return 0

def sanitize_filename(name, replacement="_"):
    valid_chars = "-_.() %s%s" % (string.ascii_letters, string.digits)
    cleaned = "".join(c if c in valid_chars else replacement for c in name).strip()
    return cleaned[:200] if cleaned else "downloaded_media"

def label_for_height(h):
    for std_h, label in STANDARD_HEIGHTS:
        if h >= std_h:
            return label
    return f"{h}p"

def height_for_label(label):
    label = label.lower().strip()
    for std_h, lab in STANDARD_HEIGHTS:
        if lab == label:
            return std_h
    m = re.match(r"(\d+)", label)
    return int(m.group(1)) if m else None

def get_ffmpeg_path():
    if getattr(sys, "frozen", False):
        # PyInstaller onefile extracts to _MEIPASS
        base = getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
    else:
        base = os.path.dirname(__file__)
    ff = os.path.join(base, "ffmpeg", "bin", "ffmpeg.exe")
    return ff if os.path.exists(ff) else "ffmpeg"

# Ensure yt-dlp/ffmpeg uses bundled binary if present
os.environ["FFMPEG_BINARY"] = get_ffmpeg_path()

# ----------------------
# GUI
# ----------------------

class DownloaderGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("hh.m4a-YT-Downloader")
        self.root.geometry("700x560")

        self.info = None
        self.download_path = os.getcwd()
        self.cancel_event = threading.Event()
        self.download_thread = None

        self.build_ui()

    def build_ui(self):
        ttk.Label(self.root, text="YouTube URL").pack(pady=6)
        self.url_entry = ttk.Entry(self.root, width=78)
        self.url_entry.pack()

        ttk.Button(self.root, text="Fetch Info", command=self.fetch_info).pack(pady=10)

        self.title_label = ttk.Label(self.root)
        self.title_label.pack()

        self.duration_label = ttk.Label(self.root)
        self.duration_label.pack()

        self.type_var = tk.StringVar(value="MP4")
        frame = ttk.Frame(self.root)
        frame.pack(pady=8)
        ttk.Radiobutton(frame, text="MP3", variable=self.type_var, value="MP3").pack(side="left", padx=6)
        ttk.Radiobutton(frame, text="MP4", variable=self.type_var, value="MP4").pack(side="left", padx=6)

        ttk.Label(self.root, text="Quality").pack()
        self.combo = ttk.Combobox(self.root, state="readonly", width=30)
        self.combo.pack()

        ttk.Button(self.root, text="Select Folder", command=self.select_folder).pack(pady=8)
        self.folder_label = ttk.Label(self.root, text=self.download_path)
        self.folder_label.pack()

        self.size_label = ttk.Label(self.root)
        self.size_label.pack()

        self.progress_var = tk.DoubleVar()
        self.progress = ttk.Progressbar(self.root, variable=self.progress_var, maximum=100, mode="determinate")
        self.progress.pack(fill="x", padx=30, pady=12)

        self.progress_text = ttk.Label(self.root, text="Ready")
        self.progress_text.pack()

        btn_frame = ttk.Frame(self.root)
        btn_frame.pack(pady=8)

        self.download_btn = ttk.Button(btn_frame, text="Download", state="disabled", command=self.start_download)
        self.download_btn.pack(side="left", padx=6)

        self.reset_btn = ttk.Button(btn_frame, text="Reset", command=self.reset_ui)
        self.reset_btn.pack(side="left", padx=6)

        # Optional: checkbox to enable android extractor client (not recommended)
        self.android_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(self.root, text="Use Android extractor client (may cause SABR issues)", variable=self.android_var).pack(pady=4)

        self.type_var.trace_add("write", lambda *a: self.update_options())

    def select_folder(self):
        folder = filedialog.askdirectory()
        if folder:
            self.download_path = folder
            self.folder_label.config(text=folder)

    def fetch_info(self):
        try:
            url = self.url_entry.get().strip()
            if not is_valid_youtube_url(url):
                raise Exception("Invalid URL")

            extractor_args = {"youtube": {"player_client": ["android"]}} if self.android_var.get() else {}
            opts = {"quiet": True, "no_warnings": True, "logger": SilentLogger(), "extractor_args": extractor_args}

            with yt_dlp.YoutubeDL(opts) as ydl:
                self.info = ydl.extract_info(url, download=False)

            self.title_label.config(text=self.info.get("title", "Unknown Title"))
            duration = self.info.get("duration")
            self.duration_label.config(text=f'{round(duration/60,2)} min' if duration else "Unknown duration")

            self.download_btn.config(state="normal")
            self.update_options()

        except Exception as exc:
            messagebox.showerror("Error", str(exc))

    def update_options(self):
        if not self.info:
            return

        if self.type_var.get() == "MP3":
            vals = ["320", "192", "128"]
        else:
            available = sorted({int(f["height"]) for f in self.info.get("formats", []) if f.get("height")}, reverse=True)
            vals = []
            for std_h, label in STANDARD_HEIGHTS:
                if any(h >= std_h for h in available):
                    vals.append(label)
            if not vals and available:
                vals = [f"{h}p" for h in available]

        self.combo["values"] = vals
        if vals:
            self.combo.current(0)
        else:
            self.combo.set("")

        if self.type_var.get() == "MP3" and self.combo.get():
            dur = self.info.get("duration", 0)
            try:
                kbps = int(self.combo.get())
                size = estimate_mp3_size(dur, kbps)
                self.size_label.config(text=f"Estimated: {size} MB")
            except Exception:
                self.size_label.config(text="")
        else:
            self.size_label.config(text="")

    def progress_hook(self, d):
        # Called from yt-dlp thread; schedule GUI updates on main thread
        if self.cancel_event.is_set():
            # abort download by raising an exception inside the download thread
            raise Exception("Download cancelled by user")
        if d.get("status") == "downloading":
            total = d.get("total_bytes") or d.get("total_bytes_estimate")
            if total and d.get("downloaded_bytes") is not None:
                percent = (d["downloaded_bytes"] / total) * 100
                self.root.after(0, lambda p=percent: (
                    self.progress_var.set(p),
                    self.progress_text.config(text=f"{p:.1f}%")
                ))
        elif d.get("status") == "finished":
            self.root.after(0, lambda: self.progress_text.config(text="Processing..."))

    def start_download(self):
        self.download_btn.config(state="disabled")
        self.cancel_event.clear()
        self.progress_var.set(0)
        self.progress_text.config(text="Starting...")
        self.download_thread = threading.Thread(target=self.download, daemon=True)
        self.download_thread.start()

    def download(self):
        extractor_args = {"youtube": {"player_client": ["android"]}} if self.android_var.get() else {}
        try:
            opts = {
                "quiet": True,
                "no_warnings": True,
                "logger": SilentLogger(),
                "extractor_args": extractor_args,
                "progress_hooks": [self.progress_hook],
            }

            title = self.info.get("title", "downloaded_media")
            safe_title = sanitize_filename(title)
            opts["outtmpl"] = os.path.join(self.download_path, f"{safe_title}.%(ext)s")

            if self.type_var.get() == "MP3":
                quality = self.combo.get() or "192"
                opts.update({
                    "format": "bestaudio",
                    "postprocessors": [{
                        "key": "FFmpegExtractAudio",
                        "preferredcodec": "mp3",
                        "preferredquality": quality
                    }]
                })
            else:
                selected_label = self.combo.get()
                chosen_height = height_for_label(selected_label)

                available_heights = sorted(
                    {int(f["height"]) for f in self.info.get("formats", [])
                    if f.get("height")},
                    reverse=True
                )

                final_h = None

                if chosen_height:
                    candidates = [h for h in available_heights if h <= chosen_height]
                    final_h = candidates[0] if candidates else (
                        available_heights[0] if available_heights else None
                    )
                else:
                    final_h = available_heights[0] if available_heights else None

                if final_h:
                    fmt = (
                        f'bestvideo[height<={final_h}][vcodec*=avc1]+'
                        f'bestaudio[acodec*=mp4a]/'
                        f'best[height<={final_h}][ext=mp4]'
                    )
                else:
                    fmt = (
                        'bestvideo[vcodec*=avc1]+'
                        'bestaudio[acodec*=mp4a]/'
                        'best[ext=mp4]'
                    )

                opts.update({
                    "format": fmt,

                    # Force universally compatible MP4
                    "merge_output_format": "mp4",

                    # Re-encode if needed
                    "postprocessor_args": [
                        "-c:v", "libx264",
                        "-c:a", "aac",
                        "-b:a", "192k",
                        "-movflags", "+faststart"
                    ]
                })
            with yt_dlp.YoutubeDL(opts) as ydl:
                ydl.download([self.url_entry.get().strip()])

            self.root.after(0, lambda: (
                self.progress_var.set(100),
                self.progress_text.config(text="Completed ✓"),
                messagebox.showinfo("Done", "Download completed")
            ))

        except Exception as exc:
            err_text = str(exc)
            # If cancelled, show a simple Ready state without error popups
            if "cancel" in err_text.lower():
                self.root.after(0, lambda: (
                    self.progress_var.set(0),
                    self.progress_text.config(text="Ready")
                ))
            else:
                self.root.after(0, lambda msg=err_text: messagebox.showerror("Error", msg))
        finally:
            self.root.after(0, lambda: self.download_btn.config(state="normal"))

    def reset_ui(self):
        # Signal cancellation and clear UI
        self.cancel_event.set()
        # Wait briefly for thread to acknowledge cancellation
        if self.download_thread and self.download_thread.is_alive():
            self.download_thread.join(timeout=0.5)
        self.url_entry.delete(0, tk.END)
        self.title_label.config(text="")
        self.duration_label.config(text="")
        self.combo["values"] = []
        self.combo.set("")
        self.size_label.config(text="")
        self.progress_var.set(0)
        self.progress_text.config(text="Ready")
        self.info = None
        self.download_btn.config(state="disabled")


def resource_path(relative_path):
    try:
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")

    return os.path.join(base_path, relative_path)
# ----------------------
# Run
# ----------------------

if __name__ == "__main__":
    root = tk.Tk()
       # GUI + taskbar icon
    try:
        root.iconbitmap(resource_path("logo.ico"))
    except:
        pass
    DownloaderGUI(root)
    root.mainloop()
