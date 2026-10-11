import os
import json
import logging
from google import genai
from google.genai import types
import cv2
import numpy as np
import random
import time

logger = logging.getLogger(__name__)

def generate_shape_combo():
    """
    Generates a structured random combination of geometric shapes and an instruction card.
    Returns (ShapeCombo_dict, instruction_card_string, freshness_tag)
    """
    shapes = ["circle", "square", "triangle", "diamond", "pentagon", "hexagon"]
    
    outer = random.choice(shapes)
    # 50% chance to have an inner shape
    has_inner = random.choice([True, False])
    inner = random.choice([s for s in shapes if s != outer]) if has_inner else "none"
    
    freshness_tag = str(random.randint(10, 99))
    
    if has_inner:
        instructions = f"Draw a large {outer}. Inside it, draw a smaller {inner}. Finally, write the number '{freshness_tag}' inside the {inner}."
    else:
        instructions = f"Draw a large {outer}. Finally, write the number '{freshness_tag}' inside the {outer}."
    
    shape_combo = {
        "outer": outer,
        "inner": inner,
        "number": freshness_tag
    }
    
    return shape_combo, instructions, freshness_tag

from django.conf import settings

def validate_focal_distance(focal_distance, homography_distance_estimate=None):
    """
    Validate focus distance with optional homography cross-check.
    """
    # Simply check min distance for now
    min_distance = getattr(settings, 'MIN_FOCAL_DISTANCE_METERS', 0.5)
    try:
        distance = float(focal_distance)
    except (TypeError, ValueError):
        return True, None # don't penalize missing metadata
        
    if distance < min_distance:
        return False, f"Photo taken too close ({distance:.2f}m)"
        
    return True, distance

def get_gemini_clients():
    try:
        from dotenv import load_dotenv
        load_dotenv()
        keys_str = os.environ.get('GEMINI_API_KEY', '')
        keys = [k.strip() for k in keys_str.split(',') if k.strip()]
        clients = []
        for k in keys:
            clients.append(genai.Client(api_key=k))
        
        if not clients:
            # Fallback for when standard environment variable discovery is preferred
            clients.append(genai.Client())
            
        return clients
    except Exception as e:
        logger.error(f"Failed to initialize Gemini clients: {e}")
        return []

def verify_teacher_reference(reference_image_bytes, expected_code, shape_data=None):
    """
    Called when a teacher uploads a reference image.
    Uses Gemini to verify that the image contains the expected code
    AND that the code is enclosed in a large hand-drawn geometric shape.
    """
    clients = get_gemini_clients()
    if not clients:
        return False, "Server error: Gemini API not configured."

    shape_instructions = ""
    if shape_data:
        outer = shape_data.get('outer', 'geometric shape')
        inner = shape_data.get('inner', 'none')
        if inner != 'none':
            shape_instructions = f"Specifically, it MUST be a {outer} containing a smaller {inner} inside of it. Reject it if the shapes do not strictly match {outer} and {inner}!"
        else:
            shape_instructions = f"Specifically, it MUST be a {outer}. Reject it if the shape is clearly not a {outer} (e.g. if you see a triangle instead of a pentagon)!"

    prompt = f"""
    You are an expert AI verification system.
    Please examine this image, which is supposed to be a hand-drawn pattern on a whiteboard.
    
    1. Does the image contain the number {expected_code}?
    2. Is the number strictly enclosed within the required LARGE, hand-drawn geometric shape? {shape_instructions}
    
    If the shape drawn does not match the requested shape(s) above, you MUST return success: false and explain the error in the message.
    
    Respond ONLY in strict JSON format with exactly two keys:
    "success": boolean (true if BOTH conditions are strictly met, false otherwise)
    "message": string (a brief explanation of why, especially if false)
    """

    try:
        last_error = None
        
        for client in clients:
            for attempt in range(3):
                try:
                    response = client.models.generate_content(
                        model='gemini-3.6-flash',
                        contents=[
                            types.Part.from_bytes(data=reference_image_bytes, mime_type='image/jpeg'),
                            prompt,
                        ],
                        config=types.GenerateContentConfig(
                            response_mime_type="application/json",
                            temperature=0.0
                        )
                    )
                    
                    # Parse the JSON response
                    text = response.text
                    # Remove markdown code blocks if present
                    if text.startswith("```json"):
                        text = text[7:-3]
                    elif text.startswith("```"):
                        text = text[3:-3]
                        
                    result = json.loads(text.strip())
                    return result.get('success', False), result.get('message', "Unknown error")
                except Exception as e:
                    error_str = str(e)
                    
                    # 429 Quota Exhausted: The key is dead for now. Don't retry on the same key, try next key immediately.
                    if "429" in error_str or "resource_exhausted" in error_str.lower() or "quota" in error_str.lower():
                        logger.warning(f"Gemini API Key Quota Exhausted: {e}. Trying next API key if available...")
                        last_error = e
                        break # Break attempt loop, move to next client

                    # 503 High Demand: Temporary Google server overload. Wait and retry.
                    elif "503" in error_str or "high demand" in error_str.lower():
                        logger.warning(f"Gemini client unavailable (503 High Demand) on attempt {attempt+1}: {e}.")
                        last_error = e
                        if attempt < 2:
                            time.sleep(2)  # Wait 2 seconds before retrying
                            continue
                        else:
                            logger.warning("Max retries reached for this API key due to 503. Trying next key...")
                            break # Break inner loop, try next client
                    
                    # Other unknown errors
                    else:
                        logger.error(f"Gemini verification failed: {e}")
                        raise Exception(f"AI Verification Service Error: {e}")
                    
        # If all keys failed
        if last_error:
            logger.error(f"All Gemini API keys failed due to quota/high demand. Last error: {last_error}")
            raise Exception(f"AI Verification Service Error (Quota/High Demand): {last_error}")
            
    except Exception as e:
        logger.error(f"Gemini verification failed: {e}")
        raise Exception(f"AI Verification Service Error: {e}")

def _bytes_to_cv2(image_bytes):
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    return img

def verify_offline_code(expected_code, reference_image, student_image, flash_fired):
    """
    Main verification pipeline using Gemini Vision AI.
    Returns (matched: bool, score: float, reasons: list)
    """
    clients = get_gemini_clients()
    if not clients:
        return False, 0.0, ["Server error: Gemini API not configured."]

    prompt = f"""
    You are an expert AI verification system for a secure attendance application.
    You will be given two images:
    Image 1 (first image): The teacher's original drawing on a whiteboard.
    Image 2 (second image): The student's photo capture.
    
    The expected verification code is: {expected_code}.
    
    Your task is to verify that the student's photo (Image 2) is a genuine capture of the EXACT SAME physical drawing shown in Image 1.
    
    Evaluate the following criteria:
    1. Does Image 2 contain the number {expected_code}?
    2. Does Image 2 contain the surrounding geometric shape pattern shown in Image 1?
    3. Crucially, are Image 1 and Image 2 photos of the EXACT SAME PHYSICAL DRAWING? Deeply analyze handwriting style, stroke thickness, irregularities in the shapes, and whiteboard artifacts.
    4. **ANTI-SPOOFING (CRITICAL):** Check if Image 2 is a photo of a piece of paper (e.g. an A4 sheet), a notebook with lines, or a digital screen (look for moiré patterns or pixel grids). If Image 1 is clearly on a whiteboard/blackboard, and Image 2 appears to be drawn on paper or displayed on a secondary phone/laptop screen to fake attendance, you MUST reject it!
    
    Respond ONLY in strict JSON format with exactly three keys:
    "success": boolean (true if it is the genuine, identical physical drawing on the same medium, false if it is a forgery, drawn on paper, or fails shape/number checks)
    "score": float (between 0.0 and 1.0 indicating your confidence in the match)
    "reasons": list of strings (brief explanations of your findings, especially if success is false, explicitly mentioning if paper/screen spoofing was detected)
    """

    try:
        def _load_image_bytes(image_file):
            if hasattr(image_file, 'open'):
                image_file.open('rb')
                image_bytes = image_file.read()
                image_file.close()
                return image_bytes
            else:
                image_file.seek(0)
                return image_file.read()
                
        ref_bytes = _load_image_bytes(reference_image)
        stu_bytes = _load_image_bytes(student_image)

        last_error = None
        
        for client in clients:
            for attempt in range(3):
                try:
                    response = client.models.generate_content(
                        model='gemini-3.6-flash',
                        contents=[
                            types.Part.from_bytes(data=ref_bytes, mime_type='image/jpeg'),
                            types.Part.from_bytes(data=stu_bytes, mime_type='image/jpeg'),
                            prompt,
                        ],
                        config=types.GenerateContentConfig(
                            response_mime_type="application/json",
                            temperature=0.0
                        )
                    )
                    
                    text = response.text
                    if text.startswith("```json"):
                        text = text[7:-3]
                    elif text.startswith("```"):
                        text = text[3:-3]
                        
                    result = json.loads(text.strip())
                    success = result.get('success', False)
                    score = float(result.get('score', 0.0))
                    reasons = result.get('reasons', [])
                    
                    return success, score, reasons
                except Exception as e:
                    error_str = str(e)
                    
                    # 429 Quota Exhausted: The key is dead for now. Don't retry on the same key, try next key immediately.
                    if "429" in error_str or "resource_exhausted" in error_str.lower() or "quota" in error_str.lower():
                        logger.warning(f"Gemini API Key Quota Exhausted: {e}. Trying next API key if available...")
                        last_error = e
                        break # Break attempt loop, move to next client

                    # 503 High Demand: Temporary Google server overload. Wait and retry.
                    elif "503" in error_str or "high demand" in error_str.lower():
                        logger.warning(f"Gemini client unavailable (503 High Demand) on attempt {attempt+1}: {e}.")
                        last_error = e
                        if attempt < 2:
                            time.sleep(2)  # Wait 2 seconds before retrying
                            continue
                        else:
                            logger.warning("Max retries reached for this API key due to 503. Trying next key...")
                            break # Break inner loop, try next client
                    
                    # Other unknown errors
                    else:
                        logger.error(f"Gemini structural verification failed: {e}")
                        raise Exception(f"AI Verification Service Error: {e}")
                    
        if last_error:
            logger.error(f"All Gemini API keys failed due to quota/high demand. Last error: {last_error}")
            raise Exception(f"AI Verification Service Error (Quota/High Demand): {last_error}")
            
    except Exception as e:
        logger.error(f"Gemini structural verification failed: {e}")
        # Raise the exception so the view can return a 503 instead of masking it as a successful review.
        raise Exception(f"AI Verification Service Error: {e}")
