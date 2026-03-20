const { exec } = require("child_process");
exec("firebase functions:log --lines 100", { cwd: "../functions" }, (error, stdout, stderr) => {
    console.log(stdout);
    console.error(stderr);
});