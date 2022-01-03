redeploy:
	git pull
	docker build -t prod .
	docker rm prod --force
	docker run -d --name prod -p 8545:8545 -t prod