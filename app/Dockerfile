# Lambda container image for transform-data.
#
# Build for the architecture the Lambda function is configured with:
#   docker buildx build --platform linux/arm64 -t transform-data:local .
FROM public.ecr.aws/lambda/python:3.13

# Install dependencies first so layer caching survives app.py edits.
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN python -m pip install --no-cache-dir --upgrade pip \
 && python -m pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt -t ${LAMBDA_TASK_ROOT}

COPY app.py ${LAMBDA_TASK_ROOT}/

# <module>.<function>
CMD ["app.handler"]
