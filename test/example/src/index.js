"use strict";
import chalk from "chalk";

console.log("Hello world!");
console.log(
  chalk.white.bold.bgBlue("I'm dependant on a third party library, see?")
);

const sleep = async (ms) => {
  return new Promise((resolve) => setTimeout(resolve, ms));
};

const exampleServer = async () => {
  for (let i = 0; i < 20; i++) {
    console.log(
      chalk.greenBright.bold(
        `I've been up for ${i} seconds`
      )
    );
    await sleep(1000);
  }
  console.log("Done");
};

exampleServer();
