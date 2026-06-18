import url from '@ohos.url';

export interface ParsedQueryParam {
  key: string;
  value: string;
  decodedValue: string;
}

export interface ParsedURLResult {
  valid: boolean;
  scheme: string;
  hostname: string;
  port: string;
  pathname: string;
  queryParams: ParsedQueryParam[];
  fragment: string;
  deepLink: ParsedURLResult | null;
  errorMessage: string;
  rawUrl: string;
}

export class URLParserUtil {
  public static parse(urlString: string): ParsedURLResult {
    const empty: ParsedURLResult = {
      valid: false,
      scheme: '',
      hostname: '',
      port: '',
      pathname: '',
      queryParams: [],
      fragment: '',
      deepLink: null,
      errorMessage: '',
      rawUrl: urlString
    };

    if (!urlString || urlString.trim().length === 0) {
      empty.errorMessage = '请输入链接';
      return empty;
    }

    let trimmedUrl = urlString.trim();

    try {
      let urlObj = new url.URL(trimmedUrl);
      let queryParams: ParsedQueryParam[] = [];

      urlObj.searchParams.forEach((value: string, key: string) => {
        let decodedValue: string = '';
        try {
          decodedValue = decodeURIComponent(value);
        } catch (e) {
          decodedValue = value;
        }
        queryParams.push({
          key: key,
          value: value,
          decodedValue: decodedValue
        });
      });

      let deepLink: ParsedURLResult | null = null;
      let deepLinkRaw = urlObj.searchParams.get('deepLink');

      if (deepLinkRaw) {
        try {
          let decodedDeepLink = decodeURIComponent(deepLinkRaw);
          deepLink = URLParserUtil.parse(decodedDeepLink);
        } catch (e) {
          deepLink = {
            valid: false,
            scheme: '',
            hostname: '',
            port: '',
            pathname: '',
            queryParams: [],
            fragment: '',
            deepLink: null,
            errorMessage: 'deepLink 解析失败: ' + JSON.stringify(e),
            rawUrl: deepLinkRaw
          };
        }
      }

      return {
        valid: true,
        scheme: urlObj.protocol.replace(':', ''),
        hostname: urlObj.hostname,
        port: urlObj.port,
        pathname: urlObj.pathname,
        queryParams: queryParams,
        fragment: urlObj.hash.replace('#', ''),
        deepLink: deepLink,
        errorMessage: '',
        rawUrl: trimmedUrl
      };
    } catch (e) {
      empty.errorMessage = '无效的 URL 格式';
      return empty;
    }
  }

  public static copyParam(param: ParsedQueryParam): string {
    return param.key + '=' + param.value;
  }

  public static copyUrl(result: ParsedURLResult): string {
    return result.rawUrl;
  }
}
