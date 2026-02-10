let i = 0;
const player = document.getElementById("player");
const files = [
  "audio/Spiritual_Healing.mp3",
  "audio/The_Philosopher.mp3",
  "audio/u1000_Eyes.mp3",
];
const riffs = [210, 76, 92];

player.src = files[i];


function Riff() {
  Jump(riffs[i]);
}

function Jump(k){
    if (player.readyState >= 1) {
    player.currentTime = k;
    } else {
        player.addEventListener("loadedmetadata", () => {
        player.currentTime = k;
        }, { once: true });
    }
}

function Next(){
    i++;
    if (i >= files.length) {
        i = 0; // loop back to first song
    }

    player.src = files[i];
    player.play();
}

function playPauseAudio() {
    if (player.paused) {
    player.play();
    } else {
    player.pause();
    }
}
player.addEventListener("ended", Next);