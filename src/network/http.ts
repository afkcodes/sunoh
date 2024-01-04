/* eslint-disable @typescript-eslint/restrict-template-expressions */
type HttpMethod = 'GET' | 'POST' | 'PUT' | 'DELETE';

interface HttpOptions {
  method?: HttpMethod;
  params?: Record<string, any>;
  headers?: Record<string, string>;
  body?: any;
  expectedStatus?: number | number[];
  responseType?: 'json' | 'text';
}

async function http<T>(url: string, options: HttpOptions = {}): Promise<T | null> {
  const {
    method = 'GET',
    params,
    headers = {},
    body,
    expectedStatus = 200,
    responseType = 'json'
  } = options;

  const requestOptions: RequestInit = {
    method,
    headers: {
      ...headers
    }
  };

  if (body && (method === 'POST' || method === 'PUT')) {
    if (body instanceof FormData) {
      requestOptions.body = body;
    } else {
      (requestOptions.headers as Record<string, string>)['content-type'] = 'application/json';
      requestOptions.body = JSON.stringify(body);
    }
  } else if (body && method !== 'POST' && method !== 'PUT') {
    const invalidMethodError = new Error('Request body is only supported for POST and PUT methods');
    console.error(`Invalid request: ${invalidMethodError.message}`);
    throw invalidMethodError;
  }

  let requestUrl = url;
  if (params) {
    const queryParams = new URLSearchParams(params);
    requestUrl += `?${queryParams.toString()}`;
  }

  try {
    const response = await fetch(requestUrl, requestOptions);

    if (
      !expectedStatus ||
      (Array.isArray(expectedStatus) && !expectedStatus.includes(response.status)) ||
      (typeof expectedStatus === 'number' && response.status !== expectedStatus)
    ) {
      const statusError = new Error(`Request failed with status ${response.status}`);
      console.error(`Request error: ${statusError.message}`);
      throw statusError;
    }

    if (responseType === 'json') {
      const responseData = (await response.json()) as T;
      return responseData;
    } else if (responseType === 'text') {
      const responseData = (await response.text()) as T;
      return responseData;
    } else {
      const invalidResponseError = new Error(`Invalid responseType: ${responseType}`);
      console.error(`Response error: ${invalidResponseError.message}`);
      throw invalidResponseError;
    }
  } catch (error: any) {
    console.error(`An error occurred: ${error.message}`);
    throw error; // Re-throw the error for higher-level error handling if needed
  }
}

export default http;
