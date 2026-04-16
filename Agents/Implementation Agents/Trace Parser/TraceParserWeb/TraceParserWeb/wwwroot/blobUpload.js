window.blobUpload = {
    /**
     * Upload a file directly to Azure Blob Storage via SAS URL.
     * Uses XMLHttpRequest (not fetch) for upload progress events.
     * @param {string} sasUrl - Full SAS URL for the blob
     * @param {string} inputElementId - DOM id of the <input type="file"> element
     * @param {object} dotNetRef - DotNetObjectReference for callbacks
     */
    upload: function (sasUrl, inputElementId, dotNetRef) {
        var input = document.getElementById(inputElementId);
        if (!input || !input.files || !input.files.length) {
            dotNetRef.invokeMethodAsync('OnUploadError', 'No file selected');
            return;
        }

        var file = input.files[0];
        var xhr = new XMLHttpRequest();
        xhr.open('PUT', sasUrl, true);
        xhr.setRequestHeader('x-ms-blob-type', 'BlockBlob');
        xhr.setRequestHeader('Content-Type', 'application/octet-stream');

        xhr.upload.onprogress = function (e) {
            if (e.lengthComputable) {
                dotNetRef.invokeMethodAsync('OnUploadProgress', e.loaded, e.total);
            }
        };

        xhr.onload = function () {
            if (xhr.status >= 200 && xhr.status < 300) {
                dotNetRef.invokeMethodAsync('OnUploadComplete');
            } else {
                dotNetRef.invokeMethodAsync('OnUploadError',
                    'HTTP ' + xhr.status + ': ' + xhr.responseText.substring(0, 500));
            }
        };

        xhr.onerror = function () {
            dotNetRef.invokeMethodAsync('OnUploadError', 'Network error — check your connection and try again.');
        };

        xhr.send(file);
    }
};
