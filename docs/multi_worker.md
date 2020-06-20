# Using multiple Robomaker workers

One way to accelerate training is to launch multiple Robomaker workers that feed into one Sagemaker instance.

The number of workers is configured through setting `system.env` `DR_WORKERS` to the desired number of workers. The result is that the number of episodes (hyperparameter `num_episodes_between_training`) will be divivided over the number of workers. The theoretical maximum number of workers equals `num_episodes_between_training`.

The training can be started as normal.

## How many workers do I need?

One Robomaker worker requires 2-4 vCPUs. Tests show that a `c5.4xlarge` instance can run 3 workers and the Sagemaker without a drop in performance. Using OpenGL images reduces the number of vCPUs required per worker.

To avoid issues with the position from which evaluations are run ensure that `( num_episodes_between_training / DR_WORKERS) * DR_TRAIN_ROUND_ROBIN_ADVANCE_DIST = 1.0`. 

Example: With 3 workers set `num_episodes_between_training: 30` and `DR_TRAIN_ROUND_ROBIN_ADVANCE_DIST=0.1`.

Note; Sagemaker will stop collecting experiences once you have reached 10.000 steps (3-layer CNN) in an iteration. For longer tracks with 600-1000 steps per completed episodes this will define the upper bound for the number of workers and episodes per iteration.

## Training on different tracks concurrently

It is also possible to use different tracks (WORLD_NAME) on each of the individual robomaker workers.  To enable, simple set DR_MULTI_TRACK=True inside run.env, then update DR_MT_WORLD_NAME_1 (etc) with the desired tracks.  This only takes effect if you are training with multiple workers, and will take precedence over the DR_WORLD_NAME parameter.  
