// Toggle the visibility of the resolution input based on the format selection
function toggleResolutionInput() {
    const format = document.getElementById("format").value;
    const resolutionLabel = document.getElementById("resolutionLabel");
    const resolutionSelect = document.getElementById("resolution");

    if (format === "mp4") {
        resolutionLabel.style.display = "block";
        resolutionSelect.style.display = "block";
    } else {
        resolutionLabel.style.display = "none";
        resolutionSelect.style.display = "none";
    }
}

// Handle the download process
function downloadContent() {
    const url = document.getElementById("url").value;
    const format = document.getElementById("format").value;
    const resolution = document.getElementById("resolution").value;
    const statusMessage = document.getElementById("statusMessage");

    if (!url) {
        statusMessage.textContent = "Please enter a valid YouTube URL.";
        return;
    }

    statusMessage.textContent = "Downloading... Please wait.";

    const requestPayload = {
        url: url,
        format: format,
        resolution: format === "mp4" ? resolution : null
    };

    // Send the request to the backend API (replace with your backend URL)
    fetch('https://your-backend-api-url.com/download', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestPayload)
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            statusMessage.textContent = "Download completed successfully!";
        } else {
            statusMessage.textContent = "Error: " + data.message;
        }
    })
    .catch(error => {
        statusMessage.textContent = "Error: " + error.message;
    });
}
