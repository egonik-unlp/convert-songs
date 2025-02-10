## Convert songs

This project is not yet functional. It's purpose is to convert music file folders into Spotify Playlists.
It works by walking the chosen folder recursively and identifiying music files, from which ID3v1 tags are extracted. 
Said tags are then are looked up against Spotify's API. Later the results of the search are used to create playlists
and then said playlist is published to the user's account.

To function, this program needs spotify API credentials and is able to access the target user account through OAuth2.

To be fully honest the purpose of this project is to be used as a Zig Lang learning experience. Zig is a really 
interesting language, but it's quite lacking in libraries and documentation. 
This of course shaped my development experience and forced me to implement almost all of the program's functionality by hand. 
Namely:

- Spotify API Interactions.
- ID3v1 parsing.
- Oauth2 auth flow (still incomplete).
- Spotify API Token management.

For now, and until I get around to making a real API for it, there are a few considerations.

- Spotify's client_id and client_secret should be included in a .env file in the root directory
- The directory name is hardcoded and set at compile time via the songs_in_dir variable in the main.zig file.
- The target playlist name and description are again hardcoded in this line in the playlist.zig file
```const body = try PlaylistRequest.build("culo", "prueba desc", true, false).stringify(self.allocator);```
where the first two params are said settings.
- This program does not work in windows yet because the .env parsing library I used does not support windows. 
I will implement this logic manually in the future.


  
