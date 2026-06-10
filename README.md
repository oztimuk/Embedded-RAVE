# Embedded RAVE - RAVEMORPH

<img width="4000" height="3000" alt="image" src="https://github.com/user-attachments/assets/9b3aad8f-905b-40e5-b1df-3840d1cdb691" />

## Introduction

As a musician I am always looking for different ways to create sounds. While I am able to play piano, my main instrument is the guitar. I have always looked at MIDI guitars and loved the idea of how they are able to change the guitar into a violin, a synth, or anything else. In this project I will use RAVE models to change the guitar input in (near) real-time into other instruments that I have trained some RAVE models on. This will then get packaged into a guitar pedal (as a tool for non-technical users) so it can be used in live performances.

To make this possible I'm combining [RAVE](https://github.com/acids-ircam/rave) models with a Raspberry Pi and a Google Colab notebook for model training. 

In creating this repo, I wanted to give people who are trying to do this type of project a shortcut and to learn from the dead ends and winding pathways that I encountered along the way.

## Hardware

* Raspberry Pi 5 with 16GB Ram (overclocked to 3Ghz)
* Waveshare 5" HDMI LCD screen (800x480)
* Geekworm Raspberry Pi 5 Brass Heatsink with Fan (To help deal with the overclocking)
* USB Audio Adapter (https://thepihut.com/products/usb-audio-adapter-works-with-raspberry-pi)
* 2 x Mono Audio Jack (Input & Output)
* 3 x 6 Pin DPDT Latching Stomp Foot Switches (not currently being used - but wired up, ready for implimentation)
* Laser cut enclosure & standoffs (plus screws, both M2 and M3) for the case

## Software

* 64bit version of PatchBox (Version: 2022-05-17) [link](https://community.blokas.io/t/beta-patchbox-os-image-2022-05-17/3774?_gl=1*2nudr*_ga*NTg3NDUwMjc0LjE3Nzg2MTkzNjQ.*_ga_0TT6SGNKV4*czE3ODAxNjIzNjkkbzYkZzEkdDE3ODAxNjI1MTckajYwJGwwJGgw)
* Build Scripts (in ```/NN_Tilde_Build_Scripts/```)
* Colab notebooks for training model (in ```/notebook```)
* [PureData (0.56-2)](https://puredata.info/downloads/pure-data)
* [nn_tilde (1.5.6)](https://github.com/acids-ircam/nn_tilde/releases/tag/v1.5.6) - used this version as 1.6.0 isn't working for Raspberry Pi.

## Instructions

Before installing Patchbox OS it is a good idea to plug in the USB Audio Adapter. This is so that the adapter is able to be seen during the setup wizard.

### First install Patchbox OS

* Download Patchbox OS from [here](https://community.blokas.io/t/beta-patchbox-os-image-2022-05-17/3774?_gl=1*2nudr*_ga*NTg3NDUwMjc0LjE3Nzg2MTkzNjQ.*_ga_0TT6SGNKV4*czE3ODAxNjIzNjkkbzYkZzEkdDE3ODAxNjI1MTckajYwJGwwJGgw)
* Follow the guide to get Patchbox working. I used the terminal as it was easier to view this on my large monitor, and using terminal commands is not an issue. 
* Make sure to select Pure Data as one of the modules to set up.

### ⚠️ Overclock the Pi... Do this at your own risk!

To ensure that inference happens on the model as quickly as possible I decided to overclock the Raspberry Pi as after initial testing of a model fouund it to be a little slow. To help speed things up, overclocking was one of a few solutions. 

To do this I opened up the ```config.txt``` file in ```/boot/firmware/``` and then added the lines:

```
force_turbo=1
arm_freq=3000
gpu_freq=1000
over_voltage=4
```

These values were derived from the Pi forums. There was a lot of discussion about it. Sadly overclocking voids the warranty, but it has helped make the sound more stable. 

### Get nn_tilde built and running

If you attempt to use the "Find externals" in PureData to get nn~ working, it will fail. It is a requirement to build from source. To do this use the ```nn_tilde_patchbox_install.sh``` script found here in the repo: [NN_Tilde_Build_Scripts/nn_tilde_patchbox_install.sh](NN_Tilde_Build_Scripts/nn_tilde_patchbox_install.sh)

This will allow you to install nn~ correctly.

### Get Pd working with your model...

A simple setup works best here. 

```
[adc~]
|
[nn~ modelname.ts encode]
|
[nn~ modelname.ts decode]
|
[dac~]

```

Obviously you can create your own patch that will mix the original signal into the final output or anything else you need to do. I've not included a patch for this as your use case may be very different. 

### Train Model

To train the model you will need a paid account with Google Colab. This is because you need to use a GPU for an extended period of time, and the free tiers won't allow for that kind of time.

If you want to use your own dataset make sure that the training data has at very least an hour of audio. More audio = better model, but has a longer training time. 

**Notes:** 

* Training doesn't stop automatically. You'll need to work out when to stop it, I'd recommend watching the IRCAM tutorials on [training a model](https://www.youtube.com/watch?v=MlbkSMLoWBk&t=582s).
* It can take quite a few days for a model to train even on a GPU, multiple GPUs won't accelerate the process because of how RAVE works with the GPU.
* During training there are three distinct phases:
  * Pretraining - doesn't take long and is a separate step (you'll only need to do this once for a new dataset).
  * Training - Can take a few days for initial training, but this is dependant on the amount of data in your training set.
  * Adversarial Training - Doesn't stop, so you will need to pick a point to stop it. The video on training a model will help you decided when to stop. Use of Tensorboard will help a lot. Don't be afraid to stop training so you can hear a new version. The notebook includes the code to restart training after you stop it.

## What my work in progress prototype looks like:

<img width="4000" height="3000" alt="image" src="https://github.com/user-attachments/assets/c12d62b9-84d0-4e76-aed7-9e38a207f1b8" />
<img width="4000" height="3000" alt="image" src="https://github.com/user-attachments/assets/8699411b-d127-4170-888a-2ff651400143" />


