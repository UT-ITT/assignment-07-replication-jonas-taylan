import cv2
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import Response
import uvicorn
from orb import process_orb, ImageProcessingError
from sift import process_sift

app = FastAPI(title="Image Matching Server")

@app.post("/match/orb")
async def match_orb_endpoint(photo: UploadFile = File(...), screen: UploadFile = File(...)):
    """Matches the uploaded photo to the screen using ORB and returns the cropped image."""
    try:
        photo_bytes = await photo.read()
        screen_bytes = await screen.read()
        
        # Process the image entirely in memory
        result_img = process_orb(photo_bytes, screen_bytes)
        
        # Encode the result back to JPEG in memory
        success, encoded_image = cv2.imencode('.jpg', result_img)
        if not success:
            raise HTTPException(status_code=500, detail="Failed to encode resulting image.")
            
        return Response(content=encoded_image.tobytes(), media_type="image/jpeg")
        
    except ImageProcessingError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.post("/match/sift")
async def match_sift_endpoint(photo: UploadFile = File(...), screen: UploadFile = File(...)):
    """Matches the uploaded photo to the screen using SIFT and returns the cropped image."""
    try:
        photo_bytes = await photo.read()
        screen_bytes = await screen.read()
        
        # Process the image entirely in memory
        result_img = process_sift(photo_bytes, screen_bytes)
        
        # Encode the result back to JPEG in memory
        success, encoded_image = cv2.imencode('.jpg', result_img)
        if not success:
            raise HTTPException(status_code=500, detail="Failed to encode resulting image.")
            
        return Response(content=encoded_image.tobytes(), media_type="image/jpeg")
        
    except ImageProcessingError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

if __name__ == "__main__":
    print("Starting server... Try sending a POST request to http://localhost:8000/match/orb")
    uvicorn.run(app, host="0.0.0.0", port=8000)
