from flask import Flask, request, jsonify
import yt_dlp

app = Flask(__name__)

@app.route('/download', methods=['POST'])
def download_content():
    data = request.get_json()
    video_url = data.get('url')
    format_choice = data.get('format')
    resolution_choice = data.get('resolution')

    if not video_url or not format_choice:
        return jsonify({"success": False, "message": "URL and format are required!"}), 400

    try:
        ydl_opts = {}

        if format_choice == 'mp3':
            ydl_opts = {
                'format': 'bestaudio/best',  # Download best audio
                'outtmpl': 'downloaded_audio.%(ext)s',  # Save as audio file
                'postprocessors': [{
                    'key': 'FFmpegAudioConvertor',
                    'preferredformat': 'mp3',  # Convert to mp3 format
                }],
            }
        elif format_choice == 'mp4':
            ydl_opts = {
                'format': f'bestvideo[height<={resolution_choice}]' if resolution_choice else 'best',
                'outtmpl': 'downloaded_video.%(ext)s',
                'merge_output_format': 'mp4',
                'postprocessors': [{
                    'key': 'FFmpegVideoConvertor',
                    'preferredformat': 'mp4',
                }],
            }
        else:
            return jsonify({"success": False, "message": "Invalid format!"}), 400

        # Download the video/audio
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([video_url])

        return jsonify({"success": True, "message": "Download completed successfully!"})

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True)
