# LingoDex - Product Requirements Document (PRD)

## 1. Product Vision

### Mission Statement
Transform everyday objects into engaging language learning moments by letting users photograph their surroundings, learn pronunciations through AI, remember newly learned vocabulary with SRS technique, and see what vocabulary friends are capturing.

### The Problem
- Traditional language learning apps feel disconnected from real life
- Vocabulary lists are boring and hard to memorize
- Pronunciation practice lacks real-time feedback
- Learners struggle to retain new words without context

### The Solution
A mobile-first language learning app where users:
- Snap photos of objects around them
- Learn the word with perfect pronunciation (AI voice)
- Practice speaking with instant accuracy feedback
- Remember through AI-generated stories using their collected words
- Ensure memorization with SRS
- Connect with friends to see what they're learning

## 2. Core Features

### 2.1 Capture & Collect (The "Pokédex" Experience)

#### Camera Mode
- Full-screen camera
- Tap to capture object photos
- Date stamp on each session
- Gallery view of captured images

#### Object Recognition
- Identifies object in photo -> returns English word (or whichever language they chose to learn; MVP will only have English, French, Spanish, Mandarin Chinese, Japanese, Korean)
- Shows translation in user's native language (e.g., "Donut" -> "甜甜圈")

#### Collection ("My Words")
- Card-based grid layout (3 columns)
- Grouped by date (e.g., "Feb 23 - 1 Word", "Feb 21 - 8 Words")
- Each card shows: photo, English word, translation
- Smooth animations (3D flip on tap)
- Search & filter by date/category

### 2.2 Pronunciation Learning

#### Listen Mode
- Tap "Pronounce" button with speaker icon
- Visual speaker pulse animation during playback
- Haptic feedback on interactions

#### Speak & Verify Mode
- Record user's pronunciation attempt
- Real-time waveform visualization
- "Try Again" option

### 2.3 Story Mode (Memory Reinforcement)

#### Trigger
- Activates after collecting 5 new words
- Bottom sheet notification: "Ready for Story Time! 📖"

#### Story Generation
- Generates 3-5 sentence story using user's recent words
- Story incorporates user's actual photos
- Tone: fun, relatable, memorable
- Example: "Yesterday I ate a donut in the forest while drinking iced tea..."

#### Story Display
- Visual story cards with user's images
- Highlighted vocabulary words (tappable for pronunciation)
- Save to "My Stories" collection
- Share story with friends

#### Vocabulary Recall (SRS + self-rating)
- Self-rating after viewing a card:
  - Again: Forgot (card shown again soon)
  - Hard: Recalled with effort (shorter interval)
  - Good: Recalled normally (optimal interval)
  - Easy: Recalled instantly (long interval)
- Algorithm (SRS):
  - Based on your rating, LingoDex calculates the next time to show you the card.
  - Difficult/incorrect cards are shown frequently until they stick.
  - Easy/known cards are shown less often, saving you time.
  - Long-term scheduling increases the interval over time (e.g., from 1 day, to 5 days, to 20 days, to months).

### 2.4 Social & Community Features

#### Authentication
- Sign in with Apple (required)
- Sign in with Google
- Email/password option
- Profile setup: name, photo, learning language

#### Friends System
- Add friends by username/link
- Friend requests (accept/decline)
- Friends list with activity status
- Remove friends option

#### Activity Feed
- Real-time updates when friends capture new words
- Feed item shows: friend's name, photo, word, timestamp
- Like/react to friends' words (emoji reactions)
- Comment option: "Great find!"

## 3. User Flows

### 3.1 Core Learning Loop
- Capture: user taps camera button -> takes photo
- Process: premium loading animation (colorful dots) -> AI identifies object
- Review: card shows object, English word, translation
- Listen: user taps "Pronounce" -> hears word
- Practice: user taps "Try It" -> records pronunciation
- Save: word added to collection with cool animation

### 3.2 Story Generation Flow
- User collects 5th word -> bottom sheet appears: "Story Time Ready!"
- Tap CTA -> "Creating your story..." (animated)
- Story displays with user's photos embedded
- User can:
  - Tap words to hear pronunciation
  - Save to Stories collection
  - Share to friends
  - Practice story reading (record & compare)

## 4. Design Principles

### Visual Design
- Style: clean, iOS-native, minimal
- Colors:
  - Primary: `#FF5A5F` (accent, CTAs)
  - Background: off-white (`#FAFAFA`)
  - Cards: white with soft `#EEEEEE` stroke
- Follow Figma for design direction

