import requests
import json
import os

# --- Configuration ---
# Replace with the actual URL of your XTTS server
BASE_URL = "http://localhost:8020" 
TEXT_TO_SPEAK = "Hello, this is a test of the XTTS system."
OUTPUT_FILENAME = "output.wav"
# Set to None to let the script automatically pick the first available speaker.
# Or, specify a speaker ID, e.g., "femaledarkelf"
SPEAKER_ID = None 
LANGUAGE = "en"

def main():
    """
    Main function to run the XTTS inference test.
    """
    print("--- Starting XTTS Inference Test Script ---")

    # 1. Get the list of available speakers from the server
    try:
        print("\n1. Fetching available speakers...")
        speakers_response = requests.get(f"{BASE_URL}/speakers")
        speakers_response.raise_for_status()  # Raise an exception for bad status codes
        
        # The API returns a list of speaker objects
        available_speakers = speakers_response.json()
        
        if not available_speakers:
            print("Error: No speakers found on the server.")
            return

        print(f"Found {len(available_speakers)} speakers.")
        
        # 2. Select a speaker
        # The speaker object contains 'name', 'voice_id', and 'preview_url'
        # We need to use the 'voice_id' for the TTS request.
        if SPEAKER_ID:
            speaker_to_use = SPEAKER_ID
        else:
            # Default to the voice_id of the first speaker in the list
            first_speaker_obj = available_speakers[0]
            speaker_to_use = first_speaker_obj.get('voice_id')
            if not speaker_to_use:
                print(f"Error: Could not find 'voice_id' in the first speaker object: {first_speaker_obj}")
                return

        print(f"\n2. Selected Speaker ID: '{speaker_to_use}'")

    except requests.exceptions.RequestException as e:
        print(f"Error fetching speakers: {e}")
        print("Please ensure the XTTS server is running at the specified BASE_URL.")
        return
    except json.JSONDecodeError:
        print("Error: Could not decode the list of speakers from the server response.")
        return

    # 3. Make the TTS request to get the audio
    print("\n3. Sending TTS request to the server...")
    # The 'speaker_wav' parameter in the API expects the speaker's voice_id
    synthesis_payload = {
        "text": TEXT_TO_SPEAK,
        "speaker_wav": speaker_to_use, 
        "language": LANGUAGE,
    }

    try:
        tts_response = requests.post(
            f"{BASE_URL}/tts_to_audio/",
            json=synthesis_payload,
            stream=True # Use stream=True to handle the audio file response
        )
        tts_response.raise_for_status()

        # 4. Save the received audio to a file
        print(f"\n4. Receiving audio data and saving to '{OUTPUT_FILENAME}'...")
        
        if 'audio/wav' not in tts_response.headers.get('content-type', ''):
            print(f"Warning: Unexpected content type received: {tts_response.headers.get('content-type')}")
            print("Server response:", tts_response.text)
            return

        with open(OUTPUT_FILENAME, "wb") as f:
            for chunk in tts_response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        print(f"\n--- Success! ---")
        print(f"Audio content has been successfully saved to '{os.path.abspath(OUTPUT_FILENAME)}'")

    except requests.exceptions.RequestException as e:
        print(f"Error during TTS request: {e}")
        if e.response:
            # The response text might contain a more specific error from the FastAPI server
            print("Server Error:", e.response.text)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    main()
