Project: Immich Video Slideshow

Purpose:
Turn an Immich video library into a continuous slideshow channel.

Code structure:
- tvos-app: native Apple TV application
- web-player: PHP slideshow player
- docker: optional deployment for web-player 

Guidelines:
- Keep dependencies minimal
- Prioritize playback performance
- Support large video libraries
- Avoid requiring external services